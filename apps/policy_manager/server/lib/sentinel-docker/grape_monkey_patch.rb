module Grape
  module Validations
    class ParamsScope
      def validates(attrs, validations)
        doc_attrs = { required: validations.keys.include?(:presence) }

        # BEGIN MONKEY PATCH
        doc_attrs[:param_type] = validations.delete(:param_type) if validations.key?(:param_type)
        # END MONKEY PATCH

        # special case (type = coerce)
        validations[:coerce] = validations.delete(:type) if validations.key?(:type)

        coerce_type = validations[:coerce]
        doc_attrs[:type] = coerce_type.to_s if coerce_type

        desc = validations.delete(:desc)
        doc_attrs[:desc] = desc if desc

        default = validations[:default]
        doc_attrs[:default] = default if default

        values = validations[:values]
        doc_attrs[:values] = values if values

        values = (values.is_a?(Proc) ? values.call : values)

        # default value should be present in values array, if both exist
        if default && values && !values.include?(default)
          raise Grape::Exceptions::IncompatibleOptionValues.new(:default, default, :values, values)
        end

        # type should be compatible with values array, if both exist
        if coerce_type && values && values.any? { |v| !v.kind_of?(coerce_type) }
          raise Grape::Exceptions::IncompatibleOptionValues.new(:type, coerce_type, :values, values)
        end

        doc_attrs[:documentation] = validations.delete(:documentation) if validations.key?(:documentation)

        full_attrs = attrs.collect { |name| { name: name, full_name: full_name(name) } }
        @api.document_attribute(full_attrs, doc_attrs)

        # Validate for presence before any other validators
        if validations.key?(:presence) && validations[:presence]
          validate('presence', validations[:presence], attrs, doc_attrs)
          validations.delete(:presence)
        end

        # Before we run the rest of the validators, lets handle
        # whatever coercion so that we are working with correctly
        # type casted values
        if validations.key? :coerce
          validate('coerce', validations[:coerce], attrs, doc_attrs)
          validations.delete(:coerce)
        end

        validations.each do |type, options|
          validate(type, options, attrs, doc_attrs)
        end
      end
    end
  end
end
