# frozen_string_literal: true

require 'active_record'

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
ActiveRecord::Base.logger = Logger.new(nil)

ActiveRecord::Schema.define do
  drop_table :test_simples, if_exists: true
  create_table :test_simples do |t|
    t.string :name
    t.boolean :flag, null: false, default: false
  end
end

class TestSimple < ActiveRecord::Base
end

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end
