# frozen_string_literal: true

module AsyncHttpPool
  module CallbackValidator
    class << self
      # Validate that the callback class defines the required methods.
      #
      # @param callback [Class, String] the callback class or its name
      # @return [void]
      # @raise [ArgumentError] if the callback class is invalid
      def validate!(callback)
        callback_class = callback.is_a?(Class) ? callback : ClassHelper.resolve_class_name(callback)

        validate_callback_method!(callback_class, :on_complete)
        validate_callback_method!(callback_class, :on_error)
      end

      # Validate callback_args and convert to a hash with string keys.
      #
      # @param callback_args [#to_h, nil] the callback arguments
      # @return [Hash, nil] validated hash with string keys, or nil
      # @raise [ArgumentError] if callback_args is invalid
      def validate_callback_args(callback_args)
        return nil if callback_args.nil?

        unless callback_args.respond_to?(:to_h)
          raise ArgumentError.new("callback_args must respond to to_h, got #{callback_args.class.name}")
        end

        hash = callback_args.to_h
        hash.each do |key, value|
          CallbackArgs.validate_value!(value, key.to_s)
        end
        hash.transform_keys(&:to_s)
      end

      private

      def validate_callback_method!(callback_class, method_name)
        unless callback_class.method_defined?(method_name)
          raise ArgumentError.new("callback class must define ##{method_name} instance method")
        end

        method = callback_class.instance_method(method_name)
        # arity of 1 = exactly 1 required arg, -1 = any args (*args), -2 = 1 required + splat
        unless method.arity == 1 || method.arity == -1 || method.arity == -2
          raise ArgumentError.new("callback class ##{method_name} must accept exactly 1 positional argument")
        end
      end
    end
  end
end
