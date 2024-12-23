module AccreditedRepresentativePortal
  module V0
    class PowerOfAttorneyRequestDecisionsController < ApplicationController
      before_action :set_power_of_attorney_request, only: [:create]
      def create
        creator_id = @current_user.id
        create_params = decision_params.merge(creator: current_user)
        reason = create_params.delete(:reason)
        reason = nil if create_params[:type] == PowerOfAttorneyRequestDecision::Types::ACCEPTANCE

        begin
          @power_of_attorney_request.create_resolution!( 
            resolving: PowerOfAttorneyRequestDecision.new(create_params), 
            reason:
          )
          resolution = @power_of_attorney_request.resolution
          if resolution.persisted?
            decision = resolution.resolving
            render json: "Decision successfully created", status: :ok
          else 
            render json: { error: 'Failed to create resolution' }, status: :unprocessable_entity
          end
        rescue ActiveRecord::RecordNotUnique => e
          Rails.logger.error("ARP: Unexpected error occurred for power of attorney request #{@power_of_attorney_request.id} - #{e.message}")
          render json: { error: 'Resolution already exists' }, status: :unprocessable_entity
        rescue => e
          Rails.logger.error("ARP: Unexpected error occurred for power of attorney request #{@power_of_attorney_request.id} - #{e.message}")
          render json: { error: 'Failed to create resolution' }, status: :unprocessable_entity
        end
      end

      private

      def set_power_of_attorney_request
        @power_of_attorney_request = PowerOfAttorneyRequest.find_by(id: params[:power_of_attorney_request_id])
        render json: { error: 'Not Found' }, status: :not_found unless @power_of_attorney_request
      end

      def decision_params
        params.require(:decision).permit(:type, :reason)
      end
    end
  end
end  
