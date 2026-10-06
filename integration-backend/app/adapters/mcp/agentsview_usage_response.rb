# typed: strict
# frozen_string_literal: true

module Adapters
  module Mcp
    # Normalizes the version-pinned AgentsView daily-usage JSON without exposing
    # archive paths, session identities, project labels, or transcript content.
    class AgentsviewUsageResponse
      extend T::Sig

      JsonObject = T.type_alias { T::Hash[String, Object] }
      Range = T.type_alias { T::Hash[String, String] }

      EXPECTED_SCHEMA_VERSION = 6
      COST_SOURCES = T.let(%w[computed reported mixed].freeze, T::Array[String])

      sig { params(document: JsonObject, range: Range, agent: T.nilable(String), source_machine: String).returns(JsonObject) }
      def self.call(document:, range:, agent:, source_machine:)
        new(document: document, range: range, agent: agent, source_machine: source_machine).serialize
      end

      sig { params(document: JsonObject, range: Range, agent: T.nilable(String), source_machine: String).void }
      def initialize(document:, range:, agent:, source_machine:)
        @document = document
        @range = range
        @agent = agent
        @source_machine = source_machine
      end

      sig { returns(JsonObject) }
      def serialize
        totals = object(@document, "totals")
        tokens = {
          "input" => nonnegative_integer(totals, "inputTokens"),
          "output" => nonnegative_integer(totals, "outputTokens"),
          "cache_creation" => nonnegative_integer(totals, "cacheCreationTokens"),
          "cache_read" => nonnegative_integer(totals, "cacheReadTokens")
        }
        pricing = object_or_nil(@document["pricing"])
        response = {
          "range" => @range,
          "agent" => @agent,
          "tokens" => tokens,
          "source" => { "machine" => @source_machine, "archive_freshness" => "synced" },
          "pricing" => pricing_metadata(pricing),
          "cost" => cost(pricing, totals, tokens)
        }
        response
      end

      sig { params(pricing: T.nilable(JsonObject)).returns(JsonObject) }
      private def pricing_metadata(pricing)
        return { "available" => false } unless pricing

        source = string(pricing, "source")
        table_version = string(pricing, "table_version")
        latest = nullable_string(pricing["latest_row_updated_at"])
        fallback = object(pricing, "fallback")
        {
          "available" => true,
          "source" => source,
          "table_version" => table_version,
          "latest_row_updated_at" => latest,
          "fallback_used" => boolean(fallback, "used")
        }
      end

      sig { params(pricing: T.nilable(JsonObject), totals: JsonObject, tokens: JsonObject).returns(JsonObject) }
      private def cost(pricing, totals, tokens)
        return { "status" => "unavailable" } unless pricing

        source = string(pricing, "cost_source")
        raise ArgumentError, "Unexpected AgentsView cost source" unless COST_SOURCES.include?(source)

        models = object(pricing, "models")
        has_token_data = tokens.values.any? { |value| value.is_a?(Integer) && value.positive? }
        has_priced_model = !models.empty?
        return { "status" => "unavailable" } unless has_token_data || source == "reported"

        amount = microdollars(totals, "totalCost")
        return { "status" => "reported", "microdollars" => amount } if source == "reported" && !has_priced_model
        return { "status" => "unavailable" } unless has_priced_model

        if unpriced_token_rows?(models)
          return { "status" => "partial_estimate", "microdollars" => amount }
        end

        status = case source
                 when "reported" then "reported"
                 when "computed" then "estimated_api"
                 when "mixed" then "mixed"
                 else raise ArgumentError, "Unexpected AgentsView cost source"
                 end
        { "status" => status, "microdollars" => amount }
      end

      sig { params(models: JsonObject).returns(T::Boolean) }
      private def unpriced_token_rows?(models)
        models.each_value.any? do |value|
          model = object_value(value)
          resolutions = array(model, "resolutions")
          resolutions.any? do |resolution|
            entry = object_value(resolution)
            entry["matched_pattern"].nil? && string(entry, "cost_source") != "reported"
          end
        end
      end

      sig { params(object: JsonObject, key: String).returns(JsonObject) }
      private def object(object, key)
        object_value(object.fetch(key))
      end

      sig { params(value: Object).returns(T.nilable(JsonObject)) }
      private def object_or_nil(value)
        return nil if value.nil?

        object_value(value)
      end

      sig { params(value: Object).returns(JsonObject) }
      private def object_value(value)
        raise ArgumentError, "Expected AgentsView object" unless value.is_a?(Hash)

        result = T.let({}, JsonObject)
        value.each do |key, item|
          raise ArgumentError, "Expected AgentsView string keys" unless key.is_a?(String)

          result[key] = item
        end
        result
      end

      sig { params(object: JsonObject, key: String).returns(T::Array[Object]) }
      private def array(object, key)
        value = object.fetch(key)
        raise ArgumentError, "Expected AgentsView array" unless value.is_a?(Array)

        value
      end

      sig { params(object: JsonObject, key: String).returns(String) }
      private def string(object, key)
        value = object.fetch(key)
        raise ArgumentError, "Expected AgentsView string" unless value.is_a?(String)

        value
      end

      sig { params(value: Object).returns(T.nilable(String)) }
      private def nullable_string(value)
        raise ArgumentError, "Expected AgentsView nullable string" unless value.nil? || value.is_a?(String)

        value
      end

      sig { params(object: JsonObject, key: String).returns(T::Boolean) }
      private def boolean(object, key)
        value = object.fetch(key)
        raise ArgumentError, "Expected AgentsView boolean" unless value == true || value == false

        value
      end

      sig { params(object: JsonObject, key: String).returns(Integer) }
      private def nonnegative_integer(object, key)
        value = object.fetch(key)
        raise ArgumentError, "Expected nonnegative AgentsView integer" unless value.is_a?(Integer) && value >= 0

        value
      end

      sig { params(object: JsonObject, key: String).returns(Integer) }
      private def microdollars(object, key)
        money = object_value(object.fetch(key))
        nonnegative_integer(money, "microdollars")
      end
    end
  end
end
