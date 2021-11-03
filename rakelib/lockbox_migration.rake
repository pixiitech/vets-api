# frozen_string_literal: true

namespace :lockbox do
  desc 're-encrypt existing db attributes after key rotation'
  task re_encrypt_records: :environment do
    HealthQuest::QuestionnaireResponse.skip_callback(:save, :before, :set_user_demographics, raise: false)

    models = ApplicationRecord.descendants.select do |model|
      model.descendants.empty? && model.try(:lockbox_attributes) && !model.lockbox_attributes.empty?
    end

    models.map(&:name).each do |m|
      encrypted_attributes = m.constantize.lockbox_attributes.keys
      puts "re-encrypting model..... #{m.constantize} Total records: #{m.constantize.count}"

      Lockbox.rotate(m.constantize, attributes: encrypted_attributes)
    end

    HealthQuest::QuestionnaireResponse.set_callback(:save, :before, :set_user_demographics, raise: false)
  end

  desc 'migrate from attr_encrypted to lockbox'
  task migrate_db: :environment do
    HealthQuest::QuestionnaireResponse.skip_callback(:save, :before, :set_user_demographics, raise: false)

    models = ApplicationRecord.descendants.select do |model|
      model.descendants.empty? && !model.encrypted_attributes.empty?
    end
    models.map(&:name).each do |m|
      puts "migrating model..... #{m.constantize}"
      Lockbox.migrate(m.constantize)
    end

    HealthQuest::QuestionnaireResponse.set_callback(:save, :before, :set_user_demographics, raise: false)
  end
end
