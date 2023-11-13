# frozen_string_literal: true

module AskVAApi
  module V0
    class InquiriesController < ApplicationController
      around_action :handle_exceptions, only: %i[index show]
      before_action :get_inquiries_by_icn, only: [:index]
      before_action :get_inquiry_by_inquiry_number, only: [:show]

      def index
        render json: @user_inquiries.payload, status: @user_inquiries.status
      end

      def show
        render json: @inquiry.payload, status: @inquiry.status
      end

      private

      def get_inquiry_by_inquiry_number
        inq = retriever.fetch_by_inquiry_number(inquiry_number: params[:inquiry_number])
        raise InvalidInquiryError if inq.inquiry_number.nil?

        @inquiry = Result.new(payload: Inquiries::Serializer.new(inq).serializable_hash, status: :ok)
      end

      def get_inquiries_by_icn
        inquiries = retriever.fetch_by_icn
        @user_inquiries = Result.new(payload: Inquiries::Serializer.new(inquiries).serializable_hash, status: :ok)
      end

      def mock_service
        DynamicsMockService.new(icn: nil, logger: nil) if params[:mock]
      end

      def retriever
        @retriever ||= Inquiries::Retriever.new(icn: current_user.icn, service: mock_service)
      end

      Result = Struct.new(:payload, :status, keyword_init: true)
      class InvalidInquiryError < StandardError; end
    end
  end
end
