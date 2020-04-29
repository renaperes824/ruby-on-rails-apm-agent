# Licensed to Elasticsearch B.V. under one or more contributor
# license agreements. See the NOTICE file distributed with
# this work for additional information regarding copyright
# ownership. Elasticsearch B.V. licenses this file to you under
# the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

# frozen_string_literal: true

module ElasticAPM
  # @api private
  module Spies
    # @api private
    class TiltSpy
      TYPE = 'template.tilt'

      def install
        ::Tilt::Template.class_eval do
          alias render_without_apm render

          def render(*args, &block)
            name = options[:__elastic_apm_template_name] || 'Unknown template'

            ElasticAPM.with_span name, TYPE do
              render_without_apm(*args, &block)
            end
          end
        end
      end
    end

    register 'Tilt::Template', 'tilt/template', TiltSpy.new
  end
end
