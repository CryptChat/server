# frozen_string_literal: true
class CreateUsers < ActiveRecord::Migration[6.0]
  def change
    create_table :users do |t|
      t.string :name, limit: 255
      t.string :country_code, null: false, limit: 10
      t.string :phone_number, null: false, limit: 50
      t.string :instance_id
      t.string :identity_key, null: false
      t.string :secret_token, null: false, limit: 32

      t.timestamps null: false
    end
    add_index :users, %i{country_code phone_number}, unique: true
    add_index :users, :instance_id, unique: true
    add_index :users, :identity_key, unique: true
  end
end
