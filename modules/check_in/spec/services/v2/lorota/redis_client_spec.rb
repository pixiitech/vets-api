# frozen_string_literal: true

require 'rails_helper'

describe V2::Lorota::RedisClient do
  subject { described_class }

  let(:opts) do
    {
      data: {
        uuid: 'd602d9eb-9a31-484f-9637-13ab0b507e0d',
        last4: '1234',
        last_name: 'Johnson'
      },
      jwt: nil
    }
  end
  let(:check_in) { CheckIn::V2::Session.build(opts) }
  let(:redis_client) { subject.build }
  let(:memory_store) { ActiveSupport::Cache.lookup_store(:memory_store) }
  let(:redis_expiry_time) { 12.hours }

  before do
    allow(Rails).to receive(:cache).and_return(memory_store)

    Rails.cache.clear
  end

  describe 'attributes' do
    it 'responds to settings' do
      expect(redis_client.respond_to?(:settings)).to be(true)
    end

    it 'gets redis_session_prefix from settings' do
      expect(redis_client.redis_session_prefix).to eq('check_in_lorota_v2')
    end

    it 'gets redis_token_expiry from settings' do
      expect(redis_client.redis_token_expiry).to eq(43_200)
    end
  end

  describe '.build' do
    it 'returns an instance of RedisClient' do
      expect(redis_client).to be_an_instance_of(V2::Lorota::RedisClient)
    end
  end

  describe '#get' do
    let(:uuid) { 'd602d9eb-9a31-484f-9637-13ab0b507e0d' }

    context 'when cache exists' do
      before do
        redis_client.save(check_in_uuid: uuid, token: '12345')
      end

      it 'returns the cached value' do
        expect(redis_client.get(check_in_uuid: uuid)).to eq('12345')
      end
    end

    context 'when cache expires' do
      let(:uuid) { Faker::Internet.uuid }

      before do
        redis_client.save(check_in_uuid: uuid, token: '52617')
      end

      it 'returns nil' do
        Timecop.travel(redis_expiry_time.from_now) do
          expect(redis_client.get(check_in_uuid: uuid)).to eq(nil)
        end
      end
    end

    context 'when cache does not exist' do
      it 'returns nil' do
        expect(redis_client.get(check_in_uuid: uuid)).to eq(nil)
      end
    end
  end

  describe '#save' do
    let(:uuid) { 'd602d9eb-9a31-484f-9637-13ab0b507e0d' }
    let(:token) { '12345' }

    it 'saves the value in cache' do
      expect(redis_client.save(check_in_uuid: uuid, token: token)).to eq(true)

      val = Rails.cache.read(
        "check_in_lorota_v2_#{uuid}_read.full",
        namespace: 'check-in-lorota-v2-cache'
      )
      expect(val).to eq(token)
    end
  end
end
