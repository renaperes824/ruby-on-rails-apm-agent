# frozen_string_literal: true

require 'spec_helper'

module ElasticAPM
  RSpec.describe Filters do
    subject { described_class.new(Config.new) }

    it 'initializes with config' do
      expect(subject).to be_a Filters::Container
    end

    describe '#add' do
      it 'can add more filters' do
        expect do
          subject.add(:thing, -> {})
        end.to change(subject.filters, :length).by 1
      end
    end

    describe '#remove' do
      it 'removes filter by key' do
        expect do
          subject.remove(:secrets)
        end.to change(subject.filters, :length).by(-1)
      end
    end

    describe '#apply' do
      it 'applies all filters to payload' do
        subject.add(:purger, ->(_payload) { {} })
        result = subject.apply(things: 1)
        expect(result).to eq({})
      end
    end
  end
end
