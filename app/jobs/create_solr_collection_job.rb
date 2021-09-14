# frozen_string_literal: true

# Create a new account-specific Solr collection using the base templates
class CreateSolrCollectionJob < ApplicationJob
  non_tenant_job

  attr_accessor :account
  ##
  # @param [Account]
  def perform(account)
    @account = account
    name = account.tenant.parameterize

    unless collection_exists? name
      client.get '/solr/admin/collections', params: collection_options.merge(action: 'CREATE',
                                                                             name: name)
    end

    account.create_solr_endpoint(url: collection_url(name), collection: name)
  end

  def without_account(name)
    return if collection_exists?(name)
    client.get '/solr/admin/collections', params: collection_options.merge(action: 'CREATE',
                                                                           name: name)
  end

  # Transform settings from nested, snaked-cased options to flattened, camel-cased options
  class CollectionOptions
    attr_reader :settings

    def initialize(settings = {})
      @settings = settings
    end

    ##
    # @example Camel-casing
    #   { replication_factor: 5 } # => { "replicationFactor" => 5 }
    # @example Blank-rejecting
    #   { emptyValue: '' } #=> { }
    # @example Nested value-flattening
    #   { collection: { config_name: 'x' } } # => { 'collection.configName' => 'x' }
    def to_h
      Hash[*settings.map { |k, v| transform_entry(k, v) }.flatten].reject { |_k, v| v.blank? }.symbolize_keys
    end

    private

      def transform_entry(k, v)
        case v
        when Hash
          v.map do |k1, v1|
            ["#{transform_key(k)}.#{transform_key(k1)}", v1]
          end
        else
          [transform_key(k), v]
        end
      end

      def transform_key(k)
        k.to_s.camelize(:lower)
      end
  end

  private

    def client
      Blacklight.default_index.connection
    end

    def collection_options
      CollectionOptions.new(account.solr_collection_options).to_h
    end

    def collection_exists?(name)
      response = client.get '/solr/admin/collections', params: { action: 'LIST' }
      collections = response['collections']

      collections.include? name
    end

    def collection_url(name)
      uri = URI(solr_url) + name

      uri.to_s
    end

    def solr_url
      @solr_url ||= ENV['SOLR_URL'] || solr_url_parts
      @solr_url = @solr_url.ends_with?('/') ? @solr_url : "#{@solr_url}/"
    end

    def solr_url_parts
      "http://#{ENV.fetch('SOLR_ADMIN_USER', 'admin')}:#{ENV.fetch('SOLR_ADMIN_PASSWORD', 'admin')}" \
        "@#{ENV.fetch('SOLR_HOST', 'solr')}:#{ENV.fetch('SOLR_PORT', '8983')}/solr/"
    end
end
