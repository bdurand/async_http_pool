# frozen_string_literal: true

class CreateAsyncHttpPoolPayloads < ActiveRecord::Migration[7.0]
  def change
    create_table :async_http_pool_payloads, id: false do |t|
      t.string :key, null: false, limit: 36
      t.text :data, null: false

      t.timestamps
    end

    add_index :async_http_pool_payloads, :key, unique: true
    add_index :async_http_pool_payloads, :created_at
  end
end
