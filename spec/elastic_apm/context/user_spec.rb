# frozen_string_literal: true

module ElasticAPM
  RSpec.describe Context::User do
    it 'sets values from passed object' do
      PossiblyUser = Struct.new(:id, :email, :username)
      record = PossiblyUser.new(1, 'a@a', 'abe')

      user = described_class.new(Config.new, record)
      expect(user.id).to eq '1'
      expect(user.email).to eq 'a@a'
      expect(user.username).to eq 'abe'
    end

    it "doesn't explode with missing methods" do
      expect do
        user = described_class.new(Config.new, Object.new)
        expect(user.id).to be_nil
        expect(user.email).to be_nil
        expect(user.username).to be_nil
      end.to_not raise_exception
    end
  end
end
