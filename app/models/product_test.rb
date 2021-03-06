class ProductTest
  include Mongoid::Document
  
  belongs_to :product
  has_one :patient_population
  has_many :test_executions, dependent: :delete
  belongs_to :user

  embeds_many :notes, inverse_of: :product_test

  # Test Details
  field :name, type: String
  field :description, type: String
  field :effective_date, type: Integer
  field :measure_ids, type: Array
  field :expected_results, type: Hash
  field :status_message, type: String
  
  validates_presence_of :name
  validates_presence_of :effective_date

  scope :order_by_type, order_by(:_type => :desc)
  
  state_machine :state, :initial => :pending  do 


   after_transition any => :ready do |test|
      test.status_message ="Ready"
      test.save
   end 


   after_transition any => :errored do |test|
      test.status_message ="Error"
      test.save
   end 

    event :ready do
      transition all => :ready
    end  
    
    event :errored do
      transition all => :error
    end
    
  end
  
  
  def self.inherited(child)  
    child.instance_eval do
      def model_name
        ProductTest.model_name
      end
    end
    super 
  end
  
  def last_execution_date

  end

  # Returns true if this ProductTests most recent TestExecution is passing
  def execution_state
    return :pending if self.test_executions.empty? 

    self.test_executions.ordered_by_date.first.state
  end
  
  def passing?
    execution_state == :passed
  end
  
  # Return all measures that are selected for this particular ProductTest
  def measures
    return [] if !measure_ids
    Measure.in(:hqmf_id => measure_ids).order_by([[:hqmf_id, :asc],[:sub_id, :asc]])
  end
  

  def records
    Record.where(:test_id => self.id)
  end

  def delete
    # Gather all records and their IDs so we can delete them along with every associated entry in the patient cache
    records = Record.where(:test_id => self.id)
    record_ids = records.map { _id }
    MONGO_DB.collection('patient_cache').remove({'value.patient_id' => {"$in" => record_ids}})
    records.destroy
    self.destroy
  end
  
  # Get the expected result for a particular measure
  def expected_result(measure)
   (expected_results || {})[measure.key]
  end
  
  # Used for downloading and e-mailing the records associated with this test.
   #
   # Returns a file that represents the test's patients given the requested format.
  def generate_records_file(format)
     file = Tempfile.new("patients-#{Time.now.to_i}")
     patients = Record.where("test_id" => self.id)
     Cypress::PatientZipper.zip(file, patients, format.to_sym)

     file
  end

  def start_date
    end_date.years_ago(1)
  end

  def end_date
    Time.at(effective_date).gmtime
  end


end