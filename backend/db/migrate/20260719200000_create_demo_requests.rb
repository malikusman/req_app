class CreateDemoRequests < ActiveRecord::Migration[7.1]
  def change
    create_table :demo_requests do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.string :company_name, null: false
      t.string :role
      t.text :notes
      t.string :source, null: false, default: "marketing"
      t.string :status, null: false, default: "new"
      t.timestamps
    end

    add_index :demo_requests, :email
    add_index :demo_requests, :status
  end
end
