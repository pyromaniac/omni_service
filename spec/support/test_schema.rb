# frozen_string_literal: true

require 'active_record'

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
ActiveRecord::Base.logger = Logger.new(nil)

ActiveRecord::Schema.define do
  create_table :test_tenants do |t|
    t.string :name
  end

  drop_table :test_simples, if_exists: true
  create_table :test_simples do |t|
    t.string :name
    t.boolean :flag, null: false, default: false
    t.references :tenant, foreign_key: { to_table: :test_tenants }
  end
end

class TestTenant < ActiveRecord::Base
end

class TestSimple < ActiveRecord::Base
  belongs_to :tenant, class_name: 'TestTenant', optional: true
end

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end
