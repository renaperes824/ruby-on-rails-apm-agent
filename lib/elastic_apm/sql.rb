# frozen_string_literal: true

module ElasticAPM
  # @api private
  module Sql
    # This method is only here as a shortcut while the agent ships with
    # both implementations ~mikker
    def self.summarizer
      @summarizer ||=
        if ElasticAPM.agent&.config&.use_legacy_sql_parser
          require 'elastic_apm/sql_summarizer'
          SqlSummarizer.new
        else
          require 'elastic_apm/sql/signature'
          Sql::Signature::Summarizer.new
        end
    end
  end
end
