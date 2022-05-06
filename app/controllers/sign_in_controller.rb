# frozen_string_literal: true

require 'sign_in/logingov/service'
require 'sign_in/idme/service'

class SignInController < ApplicationController
  skip_before_action :verify_authenticity_token, :authenticate
  before_action :authenticate_access_token, only: [:introspect]

  REDIRECT_URLS = %w[idme logingov dslogon mhv].freeze
  BEARER_PATTERN = /^Bearer /.freeze

  def authorize
    type = params[:type]
    client_state = params[:state]
    code_challenge = params[:code_challenge]
    code_challenge_method = params[:code_challenge_method]

    unless SignInController::REDIRECT_URLS.include?(type)
      raise SignIn::Errors::AuthorizeInvalidType, 'Authorization type is not valid'
    end
    raise SignIn::Errors::MalformedParamsError, 'Code Challenge is not defined' unless code_challenge
    raise SignIn::Errors::MalformedParamsError, 'Code Challenge Method is not defined' unless code_challenge_method

    state = SignIn::CodeChallengeStateMapper.new(code_challenge: code_challenge,
                                                 code_challenge_method: code_challenge_method,
                                                 client_state: client_state).perform
    render body: auth_service(type).render_auth(state: state), content_type: 'text/html'
  rescue => e
    render json: { errors: e }, status: :bad_request
  end

  def callback
    type = params[:type]
    code = params[:code]
    state = params[:state]

    unless SignInController::REDIRECT_URLS.include?(type)
      raise SignIn::Errors::CallbackInvalidType, 'Callback type is not valid'
    end
    raise SignIn::Errors::MalformedParamsError, 'Code is not defined' unless code
    raise SignIn::Errors::MalformedParamsError, 'State is not defined' unless state

    login_code, client_state = login(type, state, code)
    redirect_to login_redirect_url(login_code, client_state)
  rescue => e
    render json: { errors: e }, status: :bad_request
  end

  def token
    code = params[:code]
    code_verifier = params[:code_verifier]
    grant_type = params[:grant_type]

    raise SignIn::Errors::MalformedParamsError, 'Code is not defined' unless code
    raise SignIn::Errors::MalformedParamsError, 'Code Verifier is not defined' unless code_verifier
    raise SignIn::Errors::MalformedParamsError, 'Grant Type is not defined' unless grant_type

    user_account = SignIn::CodeValidator.new(code: code, code_verifier: code_verifier, grant_type: grant_type).perform
    session_container = SignIn::SessionCreator.new(user_account: user_account).perform

    render json: session_token_response(session_container), status: :ok
  rescue => e
    render json: { errors: e }, status: :bad_request
  end

  def refresh
    refresh_token = params[:refresh_token]
    anti_csrf_token = params[:anti_csrf_token]
    enable_anti_csrf = Settings.sign_in.enable_anti_csrf

    raise SignIn::Errors::MalformedParamsError, 'Refresh token is not defined' unless refresh_token
    if enable_anti_csrf && anti_csrf_token.nil?
      raise SignIn::Errors::MalformedParamsError, 'Anti CSRF token is not defined'
    end

    session_container = refresh_session(refresh_token, anti_csrf_token, enable_anti_csrf)

    render json: session_token_response(session_container), status: :ok
  rescue SignIn::Errors::MalformedParamsError => e
    render json: { errors: e }, status: :bad_request
  rescue => e
    render json: { errors: e }, status: :unauthorized
  end

  def revoke
    refresh_token = params[:refresh_token]
    anti_csrf_token = params[:anti_csrf_token]
    enable_anti_csrf = Settings.sign_in.enable_anti_csrf

    raise SignIn::Errors::MalformedParamsError, 'Refresh token is not defined' unless refresh_token
    if enable_anti_csrf && anti_csrf_token.nil?
      raise SignIn::Errors::MalformedParamsError, 'Anti CSRF token is not defined'
    end

    revoke_session(refresh_token, anti_csrf_token, enable_anti_csrf)

    render status: :ok
  rescue SignIn::Errors::MalformedParamsError => e
    render json: { errors: e }, status: :bad_request
  rescue => e
    render json: { errors: e }, status: :unauthorized
  end

  def introspect
    render json: @current_user, serializer: SignIn::IntrospectSerializer, status: :ok
  rescue SignIn::Errors::AccessTokenExpiredError => e
    render json: { errors: e }, status: :forbidden
  rescue => e
    render json: { errors: e }, status: :unauthorized
  end

  private

  def session_token_response(session_container)
    encrypted_refresh_token = SignIn::RefreshTokenEncryptor.new(refresh_token: session_container.refresh_token).perform
    encoded_access_token = SignIn::AccessTokenJwtEncoder.new(access_token: session_container.access_token).perform

    token_json_response(encoded_access_token, encrypted_refresh_token, session_container.anti_csrf_token)
  end

  def bearer_token(with_validation: true)
    header = request.authorization
    access_token_jwt = header.gsub(BEARER_PATTERN, '') if header&.match(BEARER_PATTERN)
    SignIn::AccessTokenJwtDecoder.new(access_token_jwt: access_token_jwt).perform(with_validation: with_validation)
  end

  def authenticate_access_token
    access_token = bearer_token
    @current_user = SignIn::UserLoader.new(access_token: access_token).perform
  rescue => e
    render json: { errors: e }, status: :unauthorized
  end

  def token_json_response(access_token, refresh_token, anti_csrf_token)
    {
      data:
        {
          access_token: access_token,
          refresh_token: refresh_token,
          anti_csrf_token: anti_csrf_token
        }
    }
  end

  def refresh_session(refresh_token, anti_csrf_token, enable_anti_csrf)
    SignIn::SessionRefresher.new(refresh_token: decrypted_refresh_token(refresh_token),
                                 anti_csrf_token: anti_csrf_token,
                                 enable_anti_csrf: enable_anti_csrf).perform
  end

  def revoke_session(refresh_token, anti_csrf_token, enable_anti_csrf)
    SignIn::SessionRevoker.new(refresh_token: decrypted_refresh_token(refresh_token),
                               anti_csrf_token: anti_csrf_token,
                               enable_anti_csrf: enable_anti_csrf).perform
  end

  def decrypted_refresh_token(refresh_token)
    SignIn::RefreshTokenDecryptor.new(encrypted_refresh_token: refresh_token).perform
  end

  def login(type, state, code)
    response = auth_service(type).token(code)

    raise SignIn::Errors::CodeInvalidError, 'Authentication Code is not valid' unless response

    user_info = auth_service(type).user_info(response[:access_token])

    normalized_attributes = auth_service(type).normalized_attributes(user_info)

    SignIn::UserCreator.new(user_attributes: normalized_attributes, state: state).perform
  end

  def login_redirect_url(login_code, client_state = nil)
    redirect_uri_params = { code: login_code }
    redirect_uri_params[:state] = client_state if client_state.present?

    redirect_uri = URI.parse(Settings.sign_in.redirect_uri)
    redirect_uri.query = redirect_uri_params.to_query
    redirect_uri.to_s
  end

  def auth_service(type)
    case type
    when 'logingov'
      logingov_auth_service
    else
      idme_auth_service(type)
    end
  end

  def idme_auth_service(type)
    @idme_auth_service ||= begin
      @idme_auth_service = SignIn::Idme::Service.new
      @idme_auth_service.type = type
      @idme_auth_service
    end
  end

  def logingov_auth_service
    @logingov_auth_service ||= SignIn::Logingov::Service.new
  end
end
