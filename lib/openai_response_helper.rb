module OpenaiResponseHelper
  private

  def normalize_response_hash(obj)
    return {} if obj.nil?

    hash =
      if obj.respond_to?(:deep_to_h)
        obj.deep_to_h
      elsif obj.respond_to?(:to_h)
        obj.to_h
      else
        obj
      end

    deep_stringify_keys(hash)
  end

  def deep_stringify_keys(value)
    case value
    when Hash
      value.each_with_object({}) { |(k, v), acc| acc[k.to_s] = deep_stringify_keys(v) }
    when Array
      value.map { |v| deep_stringify_keys(v) }
    else
      value
    end
  end
end
