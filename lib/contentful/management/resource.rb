require_relative 'resource/system_properties'
require_relative 'resource/refresher'
require 'date'

module Contentful
  module Management
    # Include this module to declare a class to be a contentful resource.
    # This is done by the default in the existing resource classes
    #
    # You can define your own classes that behave like contentful resources:
    # See examples/custom_classes.rb to see how.
    #
    # Take a look at examples/resource_mapping.rb on how to register them to be returned
    # by the client by default
    module Resource
      COERCIONS = {
        string: ->(value) { !value.nil? ? value.to_s : nil },
        integer: ->(value) { value.to_i },
        float: ->(value) { value.to_f },
        boolean: ->(value) { !!value },
        date: ->(value) { !value.nil? ? DateTime.parse(value) : nil }
      }

      attr_reader :properties, :request, :client, :default_locale, :raw_object

      def initialize(object = nil, request = nil, client = nil, nested_locale_fields = false, default_locale = Contentful::Management::Client::DEFAULT_CONFIGURATION[:default_locale])
        self.class.update_coercions!
        @nested_locale_fields = nested_locale_fields
        @default_locale = default_locale

        @properties = extract_from_object object, :property, self.class.property_coercions.keys
        @request = request
        @client = client
        @raw_object = object
      end

      def inspect(info = nil)
        properties_info = properties.empty? ? '' : " @properties=#{ properties.inspect }"
        "#<#{ self.class }:#{ properties_info }#{ info }>"
      end

      # Returns true for resources that behave like an array
      def array?
        false
      end

      # By default, fields come flattened in the current locale. This is different for syncs
      def nested_locale_fields?
        !!@nested_locale_fields
      end

      # Resources that don't include SystemProperties return nil for #sys
      def sys
        nil
      end

      # Resources that don't include Fields or AssetFields return nil for #fields
      def fields
        nil
      end

      # Shared instance of the API client
      def client
        Contentful::Management::Client.shared_instance
      end

      private

      def extract_from_object(object, namespace, keys = nil)
        if object
          keys ||= object.keys
          keys.each.with_object({}) do |name, res|
            res[name.to_sym] = coerce_value_or_array(
                object.is_a?(::Array) ? object : object[name.to_s],
                self.class.public_send(:"#{ namespace }_coercions")[name.to_sym]
            )
          end
        else
          {}
        end
      end

      def coerce_value_or_array(value, what = nil)
        if value.is_a? ::Array
          value.map { |row| coerce_or_create_class(row, what) }
        else
          coerce_or_create_class(value, what)
        end
      end

      def coerce_or_create_class(value, what)
        case what
          when Symbol
            COERCIONS[what] ? COERCIONS[what][value] : value
          when Class
            what.new(value, client)
          else
            value
        end
      end

      # Register the resources properties on class level by using the #property method
      module ClassMethods
        # By default, fields come flattened in the current locale. This is different for sync
        def nested_locale_fields?
          false
        end

        def property_coercions
          @property_coercions ||= {}
        end

        # Shared instance of the API client
        def client
          Contentful::Management::Client.shared_instance
        end

        # Defines which properties of a resource your class expects
        # Define them in :camelCase, they will be available as #snake_cased methods
        #
        # You can pass in a second "type" argument:
        # - If it is a class, it will be initialized for the property
        # - Symbols are looked up in the COERCION constant for a lambda that
        #   defines a type conversion to apply
        #
        # Note: This second argument is not meant for contentful sub-resources,
        # but for structured objects (like locales in a space)
        # Sub-resources are handled by the resource builder
        def property(name, property_class = nil)
          property_coercions[name.to_sym] = property_class
          accessor_name = Contentful::Management::Support.snakify(name)
          define_method accessor_name do
            properties[name.to_sym]
          end
          define_method "#{ accessor_name }=" do |value|
            properties[name.to_sym] = value
          end
        end

        # Ensure inherited classes pick up coercions
        def update_coercions!
          return if @coercions_updated

          if superclass.respond_to? :property_coercions
            @property_coercions = superclass.property_coercions.dup.merge(@property_coercions || {})
          end

          if superclass.respond_to? :sys_coercions
            @sys_coercions = superclass.sys_coercions.dup.merge(@sys_coercions || {})
          end

          if superclass.respond_to? :fields_coercions
            @fields_coercions = superclass.fields_coercions.dup.merge(@fields_coercions || {})
          end

          @coercions_updated = true
        end
      end

      def self.included(base)
        base.extend(ClassMethods)
      end
    end
  end
end
