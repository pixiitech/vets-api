# frozen_string_literal: true

require 'rails_helper'
require 'sidekiq/testing'

RSpec.describe RapidReadyForDecision::AsthmaProcessor, type: :worker do
  before do
    Sidekiq::Worker.clear_all
  end

  let!(:user) { FactoryBot.create(:disabilities_compensation_user, icn: '2000163') }
  let(:auth_headers) do
    EVSS::DisabilityCompensationAuthHeaders.new(user).add_headers(EVSS::AuthHeaders.new(user).to_h)
  end
  let(:saved_claim) { FactoryBot.create(:va526ez) }
  let(:submission) do
    create(:form526_submission, :with_uploads, :asthma_claim_for_increase,
           user_uuid: user.uuid,
           auth_headers_json: auth_headers.to_json,
           saved_claim_id: saved_claim.id,
           submitted_claim_id: '600130094')
  end

  describe '#perform', :vcr do
    around do |example|
      VCR.use_cassette('evss/claims/claims_without_open_compensation_claims', &example)
    end

    it 'finishes successfully' do
      Sidekiq::Testing.inline! do
        rrd_sidekiq_job = RapidReadyForDecision::Constants::DISABILITIES[:asthma][:sidekiq_job]
        rrd_sidekiq_job.constantize.perform_async(submission.id)

        submission.reload
        expect(submission.form.dig('rrd_metadata', 'pdf_guid').length).to be > 20
      end
    end
  end

  describe '#assess_data', :vcr do
    subject { described_class.new(submission).assess_data }

    context 'when there are active medication requests' do
      it 'returns the active medication requests' do
        expect(subject[:medications].count).to eq(11)
      end
    end

    it 'flags potential asthma-related medication' do
      expect(subject[:medications].select { |med| med[:flagged] }.count).to eq(3)
    end

    it 'correctly orders potential asthma-related medication to appear first' do
      expect(subject[:medications].take(3).all? { |med| med[:flagged] }).to eq true
    end
  end

  describe '#release_pdf?' do
    subject { described_class.new(submission).release_pdf? }

    it 'returns false when Flipper symbol is disabled' do
      Flipper.disable(:rrd_asthma_release_pdf)
      expect(subject).to eq false
    end

    it 'returns true when Flipper symbol is enabled' do
      Flipper.enable(:rrd_asthma_release_pdf)
      expect(subject).to eq true
    end
  end
end
