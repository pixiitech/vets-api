# frozen_string_literal: true

module AccreditedRepresentativePortal
  class PowerOfAttorneyRequest < ApplicationRecord
    module ClaimantTypes
      DEPENDENT = 'dependent'
      VETERAN = 'veteran'
    end

    belongs_to :claimant, class_name: 'UserAccount'

    has_one :power_of_attorney_form,
            inverse_of: :power_of_attorney_request,
            required: true

    has_one :resolution,
            class_name: 'AccreditedRepresentativePortal::PowerOfAttorneyRequestResolution',
            inverse_of: :power_of_attorney_request

    belongs_to :power_of_attorney_holder,
               inverse_of: :power_of_attorney_requests,
               polymorphic: true

    belongs_to :accredited_individual

    before_validation :set_claimant_type

    private

    def set_claimant_type
      self.claimant_type = if power_of_attorney_form.parsed_data['dependent']
                             ClaimantTypes::DEPENDENT
                           elsif power_of_attorney_form.parsed_data['veteran']
                             ClaimantTypes::VETERAN
                           end
    end
  end
end
