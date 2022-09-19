# frozen_string_literal: true

module SignIn
  class CredentialLevelCreator
    attr_reader :requested_acr, :type, :id_token, :user_info

    def initialize(requested_acr:, type:, id_token:, user_info:)
      @requested_acr = requested_acr
      @type = type
      @id_token = id_token
      @user_info = user_info
    end

    def perform
      create_credential_level
    end

    private

    def create_credential_level
      CredentialLevel.new(requested_acr: requested_acr,
                          credential_type: type,
                          current_ial: current_ial,
                          max_ial: max_ial)
    rescue ActiveModel::ValidationError
      raise Errors::InvalidCredentialLevelError, message: 'Unsupported credential authorization levels'
    end

    def max_ial
      case type
      when SAML::User::LOGINGOV_CSID
        verified_ial_level(user_info.verified_at)
      when SAML::User::MHV_ORIGINAL_CSID
        verified_ial_level(LOA::MHV_PREMIUM_VERIFIED.include?(user_info.mhv_assurance))
      when SAML::User::DSLOGON_CSID
        Rails.logger.info("[CredentialLevelCreator] DSLogon level of assurance #{user_info.dslogon_assurance}")
        verified_ial_level(LOA::DSLOGON_PREMIUM_VERIFIED.include?(user_info.dslogon_assurance))
      else
        verified_ial_level(user_info.level_of_assurance == LOA::THREE)
      end
    end

    def current_ial
      case type
      when SAML::User::LOGINGOV_CSID
        acr = JWT.decode(id_token, nil, false).first['acr']
        verified_ial_level(acr == IAL::LOGIN_GOV_IAL2 || previously_verified?(:logingov_uuid))
      when SAML::User::MHV_ORIGINAL_CSID
        verified_ial_level(requested_verified_account? && LOA::MHV_PREMIUM_VERIFIED.include?(user_info.mhv_assurance))
      when SAML::User::DSLOGON_CSID
        verified_ial_level(requested_verified_account? &&
                           LOA::DSLOGON_PREMIUM_VERIFIED.include?(user_info.dslogon_assurance))
      else
        verified_ial_level(user_info.credential_ial == LOA::IDME_CLASSIC_LOA3 || previously_verified?(:idme_uuid))
      end
    end

    def verified_ial_level(verified)
      verified ? IAL::TWO : IAL::ONE
    end

    def requested_verified_account?
      [Constants::Auth::IAL2, Constants::Auth::LOA3, Constants::Auth::MIN].include?(requested_acr)
    end

    def previously_verified?(identifier_type)
      return false unless Settings.sign_in.auto_uplevel && requested_verified_account?

      user_verification = UserVerification.find_by(identifier_type => user_info.sub)
      user_verification&.verified?
    end
  end
end
