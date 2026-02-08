# frozen_string_literal: true

class ActiveRecordHelper
  class << self
    def available?
      @available ||= begin
        require "active_record"
        true
      rescue LoadError
        false
      end
    end

    def setup
      return unless available?

      # Set up in-memory SQLite database before requiring the store.
      # A :memory: database exists only on the single connection, so the pool is
      # intentionally sized to 1.  The thread safety test serialises through that
      # connection via with_connection blocks.
      ActiveRecord::Base.establish_connection(
        adapter: "sqlite3",
        database: ":memory:",
        pool: 1,
        wait_timeout: 30
      )

      # Silence ActiveRecord schema output
      ActiveRecord::Schema.verbose = false

      # Create the table
      ActiveRecord::Schema.define do
        create_table :async_http_pool_payloads, id: false, force: true do |t|
          t.string :key, null: false, limit: 36
          t.text :data, null: false

          t.timestamps
        end

        add_index :async_http_pool_payloads, :key, unique: true
        add_index :async_http_pool_payloads, :created_at
      end

      # Release the connection so it's available to tests
      ActiveRecord::Base.connection_pool.release_connection
    end

    def flushdb
      return unless available?

      AsyncHttpPool::PayloadStore::ActiveRecordStore::Payload.delete_all
    end
  end
end
