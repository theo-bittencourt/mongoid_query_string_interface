require 'spec_helper'

class Document
  include Mongoid::Document
  extend Mongoid::QueryStringInterface

  field :title
  field :some_integer, :type => Integer
  field :some_float, :type => Float
  field :created_at, :type => Time
  field :tags, :type => Array
  field :status

  embeds_one :embedded_document

  def self.default_filtering_options
    { :status => 'published' }
  end

  def self.default_sorting_options
    ['created_at.desc', 'updated_at.asc']
  end

  def self.filtering_attributes_to_replace
    { :names => :tags }
  end

  def self.sorting_attributes_to_replace
    { :fullnames => :tags, :updated_at => :updated_at_sortable}
  end

  def self.paginatable_collection_from(collection, total, params)
    results_with_pager(collection, total, params)
  end
end

module MyTests
  class SimpleDocument
    include Mongoid::Document
    extend Mongoid::QueryStringInterface

    field :title
  end
end

class EmbeddedDocument
  include Mongoid::Document

  field :name
  field :tags, :type => Array

  embedded_in :document, :inverse_of => :embedded_document
end

describe Mongoid::QueryStringInterface do
  let! :document do
    Document.create :title => 'Some Title', :some_integer => 1, :some_float => 1.1, :status => 'published',
                    :created_at => 5.days.ago.to_time, :tags => ['esportes', 'basquete', 'flamengo'],
                    :some_boolean => true, :other_boolean => false, :nil_value => nil,
                    :embedded_document => { :name => 'embedded document',
                      :tags => ['bar', 'foo', 'yeah'] }
  end

  let! :other_document do
    Document.create :title => 'Some Other Title', :some_integer => 2, :some_float => 2.2, :status => 'published',
                    :created_at => 2.days.ago.to_time, :tags => ['esportes', 'futebol', 'jabulani', 'flamengo'],
                    :some_boolean => false, :other_boolean => true, :nil_value => 'not_nil',
                    :embedded_document => { :name => 'other embedded document',
                      :tags => ['yup', 'uhu', 'yeah', 'H4', '4H', '4H4', 'H4.1', '4.1H', '4.1H4.1'] }
  end

  describe "defaults" do
    it "should return an empty hash as the default filtering options" do
      MyTests::SimpleDocument.default_filtering_options.should == {}
    end

    it "should return an empty array as the default sorting options" do
      MyTests::SimpleDocument.default_sorting_options.should == []
    end

    it "should return hash with per_page => 12 and page => 1 for the default pagination options" do
      MyTests::SimpleDocument.default_pagination_options.should == { :per_page => 12, :page => 1 }
    end

    it "should return an empty hash as the default sorting attributes to replace" do
      MyTests::SimpleDocument.sorting_attributes_to_replace.should == {}
    end

    it "should return an empty hash as the default filtering attributes to replace" do
      MyTests::SimpleDocument.filtering_attributes_to_replace.should == {}
    end
  end

  context 'with default filtering options' do
    it 'should use the default filtering options' do
      Document.create :status => 'not published' # this should not be retrieved
      Document.filter_by.should == [other_document, document]
    end
  end

  context 'with default sorting options' do
    it 'should use the default sorting options if no sorting option is given' do
      Document.filter_by.should == [other_document, document]
    end

    it 'should use the given order_by and ignore the default sorting options' do
      Document.filter_by('order_by' => 'created_at.asc').should == [document, other_document]
    end
  end

  context "when filtering with pagination" do
    it "should filter by given params" do
      params = { 'title' => 'title' }
      collection = mock(WillPaginate::Collection).as_null_object
      Document.should_receive(:filter_by).with(params).and_return(collection)
      Document.filter_with_pagination_by(params)
    end

    it "should return a pager" do
      params = { 'title' => 'title' }
      collection = mock(WillPaginate::Collection).as_null_object
      Document.stub(:filter_by).with(params).and_return(collection)
      Document.filter_with_pagination_by(params).should have_key(:pager)
    end

    it "should return results using human model name" do
      params = { 'title' => 'title' }
      collection = mock(WillPaginate::Collection).as_null_object
      MyTests::SimpleDocument.stub(:filter_by).with(params).and_return(collection)
      MyTests::SimpleDocument.filter_with_pagination_by(params).should have_key(:simple_documents)
    end
  end

  context "when filtering with optimized pagination" do
    it "should use default parameters" do
      params = { 'title' => 'title' }
      mock_criteria = mock(Mongoid::Criteria)
      Document.should_receive(:filter_only_and_order_by).with(params).and_return(mock_criteria)
      mock_criteria.should_receive(:skip).with(0).and_return(mock_criteria)
      mock_criteria.should_receive(:limit).with(12)
      Document.filter_with_optimized_pagination_by(params)
    end

    it "should use given pager parameters" do
      params = { 'title' => 'title', 'per_page' => 100, 'page' => 3 }
      mock_criteria = mock(Mongoid::Criteria)
      Document.should_receive(:filter_only_and_order_by).with(params).and_return(mock_criteria)
      mock_criteria.should_receive(:skip).with(200).and_return(mock_criteria)
      mock_criteria.should_receive(:limit).with(100)
      Document.filter_with_optimized_pagination_by(params)
    end
  end

  context 'with pagination' do
    before :each do
      @context = mock('context')
      Document.stub!(:where).and_return(@context)
      @context.stub!(:order_by).and_return(@context)
      @context.stub!(:filter_fields_by).and_return(@context)
    end

    it "should add a paginate method to the document" do
      Document.should respond_to(:paginate)
    end

    it 'should paginate the result by default' do
      @context.should_receive(:paginate).with('page' => 1, 'per_page' => 12)
      Document.filter_by
    end

    it 'should use the page and per_page parameters if they are given' do
      @context.should_receive(:paginate).with('page' => 3, 'per_page' => 20)
      Document.filter_by 'page' => 3, 'per_page' => 20
    end

    context "of a document that already has a paginate method" do
      class SelfPaginatedDocument
        def self.paginate(options)
          options
        end

        extend Mongoid::QueryStringInterface
      end

      it "should not change the .paginate method of that document" do
        options = { :per_page => 5, :page => 3 }
        SelfPaginatedDocument.paginate(options).should == options
      end
    end
  end

  context 'with sorting' do
    it 'should use order_by parameter to sort' do
      Document.filter_by('order_by' => 'created_at.desc').should == [other_document, document]
    end

    it 'should use asc as default if only the attribute name is given' do
      Document.filter_by('order_by' => 'created_at').should == [document, other_document]
    end

    context 'with more than one field' do
      let :another_document do
        Document.create :title => 'Another Title', :some_integer => 5, :some_float => 5.5, :status => 'published',
                        :created_at => 2.days.ago.to_time, :tags => ['esportes', 'futebol', 'jabulani', 'flamengo'],
                        :some_boolean => false, :other_boolean => true, :nil_value => 'not_nil',
                        :embedded_document => { :name => 'other embedded document',
                          :tags => ['yup', 'uhu', 'yeah', 'H4', '4H', '4H4', 'H4.1', '4.1H', '4.1H4.1'] }
      end

      before { another_document }

      it 'should use accept an list of fields to order, separated by "|", using ascending order as default' do
        document.update_attributes         title: 'AAA', created_at: Time.now - 5.days
        other_document.update_attributes   title: 'AAA', created_at: Time.now - 3.days
        another_document.update_attributes title: 'BBB', created_at: Time.now
        
        Document.filter_by('order_by' => 'title|created_at').should == [document, other_document, another_document]
      end

      it 'should use accept an list of fields to order, separated by "|", mixing default and given direction' do
        Document.filter_by('order_by' => 'created_at.desc|title').should == [another_document, other_document, document]
      end

      it 'should use accept an list of fields to order, separated by "|", using given direction for each' do
        document.update_attributes         title: 'AAA', created_at: Time.now - 5.days
        other_document.update_attributes   title: 'AAA', created_at: Time.now - 3.days
        another_document.update_attributes title: 'BBB', created_at: Time.now
        Document.filter_by('order_by' => 'title.desc|created_at.desc').should == [another_document, other_document, document]
      end
    end
  end

  context 'when #filter_with_pagination_by receive a block' do
    before do
      Document.delete_all

      @b_document = Document.create title: 'B Title', status: 'published'
      @c_document = Document.create title: 'C Title', status: 'published'
      @a_document = Document.create title: 'A Title', status: 'published'

      @result = Document.filter_with_pagination_by({}) do |collection|
        collection.order_by(:title.asc)
      end
    end

    it { @result[:documents].should eq [@a_document, @b_document, @c_document] }
  end

  context 'with filtering' do
    it 'should use a simple filter on a document attribute' do
      Document.filter_by('title' => document.title).should == [document]
    end

    it 'should use a complex filter in an embedded document attribute' do
      Document.filter_by('embedded_document.name' => document.embedded_document.name).should == [document]
    end

    it 'should ignore pagination parameters' do
      Document.filter_by('title' => document.title, 'page' => 1, 'per_page' => 20).should == [document]
    end

    it 'should ignore order_by parameters' do
      Document.filter_by('title' => document.title, 'order_by' => 'created_at').should == [document]
    end

    it 'should ignore controller, action and format parameters' do
      Document.filter_by('title' => document.title, 'controller' => 'documents', 'action' => 'index', 'format' => 'json').should == [document]
    end

    it 'should accept simple regex values' do
      Document.filter_by('title' => '/ome Tit/').should == [document]
    end

    it 'should accept regex values with modifiers' do
      Document.filter_by('title' => '/some title/i').should == [document]
    end

    it 'should not raise error if empty values are used' do
      lambda { Document.filter_by('title' => '') }.should_not raise_error
    end

    it 'should unescape all values in the URI' do
      Document.filter_by('title' => 'Some%20Title').should == [document]
    end

    context 'with conditional operators' do
      let :default_parameters do
        Document.default_filtering_options.inject({}) { |r, i| k, v = i; r[k.to_s] = v; r }
      end

      let :criteria do
        criteria = mock(Mongoid::Criteria)
        criteria.stub!(:where).and_return(criteria)
        criteria.stub!(:order_by).and_return(criteria)
        criteria.stub!(:paginate).and_return(criteria)
        criteria.stub!(:filter_fields_by).and_return(criteria)
        criteria
      end

      it 'should use it when given as the last portion of attribute name' do
        Document.filter_by('title.ne' => 'Some Other Title').should == [document]
      end

      it 'should accept different conditional operators for the same attribute' do
        Document.filter_by('created_at.gt' => 6.days.ago.to_s, 'created_at.lt' => 4.days.ago.to_s).should == [document]
      end

      context 'with date values' do
        it 'should parse a date correctly' do
          Document.filter_by('created_at' => document.created_at.to_s).should == [document]
        end
      end

      context 'with number values' do
        it 'should parse a integer correctly' do
          Document.filter_by('some_integer.lt' => '2').should == [document]
        end

        it 'should not parse as an integer if it does not starts with a digit' do
          Document.filter_by('embedded_document.tags' => 'H4').should == [other_document]
        end

        it 'should not parse as an integer if it does not ends with a digit' do
          Document.filter_by('embedded_document.tags' => '4H').should == [other_document]
        end

        it 'should not parse as an integer if it has a non digit character in it' do
          Document.filter_by('embedded_document.tags' => '4H4').should == [other_document]
        end

        it 'should parse a float correctly' do
          Document.filter_by('some_float.lt' => '2.1').should == [document]
        end

        it 'should not parse as a float if it does not starts with a digit' do
          Document.filter_by('embedded_document.tags' => 'H4.1').should == [other_document]
        end

        it 'should not parse as a float if it does not ends with a digit' do
          Document.filter_by('embedded_document.tags' => '4.1H').should == [other_document]
        end

        it 'should not parse as a float if it has a non digit character in it' do
          Document.filter_by('embedded_document.tags' => '4.1H4.1').should == [other_document]
        end
      end

      context 'with regex values' do
        it 'should accept simple regex values' do
          Document.filter_by('title.in' => '/ome Tit/').should == [document]
        end

        it 'should accept regex values with modifiers' do
          Document.filter_by('title.in' => '/some title/i').should == [document]
        end
      end

      context 'with boolean values' do
        it 'should accept "true" string as a boolean value' do
          Document.filter_by('some_boolean' => 'true').should == [document]
        end

        it 'should accept "false" string as a boolean value' do
          Document.filter_by('other_boolean' => 'false').should == [document]
        end
      end

      context 'with nil value' do
        it 'should accept "nil" string as nil value' do
          Document.filter_by('nil_value' => 'nil').should == [document]
        end
      end

      context 'with array values' do
        let :document_with_similar_tags do
          Document.create :title => 'Some Title', :some_number => 1, :status => 'published',
                          :created_at => 5.days.ago.to_time, :tags => ['esportes', 'basquete', 'flamengo', 'rede globo', 'esporte espetacular']
        end

        it 'should convert values into arrays for operator $all' do
          Document.filter_by('tags.all' => document.tags.join('|')).should == [document]
        end

        it 'should convert values into arrays for operator $in' do
          Document.filter_by('tags.in' => 'basquete|futebol').should == [other_document, document]
        end

        it 'should convert values into arrays for operator $nin' do
          Document.create :tags => ['futebol', 'esportes'], :status => 'published' # should not be retrieved
          Document.filter_by('tags.nin' => 'jabulani|futebol').should == [document]
        end

        it 'should convert single values into arrays for operator $all' do
          Document.filter_by('tags.all' => 'basquete').should == [document]
        end

        it 'should convert single values into arrays for operator $in' do
          Document.filter_by('tags.in' => 'basquete').should == [document]
        end

        it 'should convert single values into arrays for operator $nin' do
          Document.filter_by('tags.nin' => 'jabulani').should == [document]
        end

        it "should properly use the $in operator when only one integer value is given" do
          Document.filter_by("some_integer.in" => "1").should == [document]
        end

        it "should properly use the $in operator when only one float value is given" do
          Document.filter_by("some_float.in" => "1.1").should == [document]
        end

        it "should properly use the $in operator when only one date time value is given" do
          Document.filter_by("created_at.in" => document.created_at.iso8601).should == [document]
        end

        it 'should accept different conditional operators for the same attribute' do
          document_with_similar_tags
          Document.filter_by('tags.all' => 'esportes|basquete', 'tags.nin' => 'rede globo|esporte espetacular').should == [document]
        end
      end

      context "with 'or' attribute" do
        it "should accept a json with query data" do
          Document.filter_by('or' => '[{"tags.all": "flamengo|basquete"}, {"tags.all": "flamengo|jabulani"}]').should == [other_document, document]
        end

        it "should unescape the json" do
          Document.filter_by('or' => '[{"tags.all":%20"flamengo%7Cbasquete"},%20{"tags.all":%20"flamengo%7Cjabulani"}]').should == [other_document, document]
        end

        it "should accept any valid mongodb query" do
          Document.filter_by('or' => '[{"tags.all": ["flamengo", "basquete"]}, {"tags": {"$all" : ["flamengo", "jabulani"]}}]').should == [other_document, document]
        end

        context "with other parameters outside $or" do
          context "that use array conditional operators" do
            context "with single values" do
              it "should merge outside parameters into $or clauses" do
                Document.should_receive(:where)
                        .with(default_parameters.merge('$or' => [{'tags' => { "$all" => ['basquete', 'flamengo'] }}, {'tags' => { "$all" => ['jabulani', 'flamengo'] }}]))
                        .and_return(criteria)

                Document.filter_by('tags.all' => 'flamengo', 'or' => '[{"tags.all": ["basquete"]}, {"tags.all" : ["jabulani"]}]')
              end
            end
          end
        end
      end

      context "when disabling default filtering options" do
        it "should use only the outside parameters" do
          Document.should_receive(:where).with("tags"=>{"$all"=>["flamengo"]}).and_return(criteria)
          Document.filter_by('tags.all' => 'flamengo', :disable_default_filters => nil)
        end
      end

      context "when give replace attributes for filtering" do
        it "should use the replace attribute for the outside parameters" do
          Document.should_receive(:where).with(default_parameters.merge("tags"=>"flamengo")).and_return(criteria)
          Document.filter_by('names' => 'flamengo')
        end

        it "should use the replace attribute for the outside parameters with modifiers" do
          Document.should_receive(:where).with(default_parameters.merge("tags"=>{"$all"=>["flamengo"]})).and_return(criteria)
          Document.filter_by('names.all' => 'flamengo')
        end

        it "should use the replace attribute for the outside parameters with modifiers merging with outside parameters into $or clauses" do
          Document.should_receive(:where)
                  .with(default_parameters.merge('$or' => [{'tags' => { "$all" => ['basquete', 'flamengo'] }}, {'tags' => { "$all" => ['jabulani', 'flamengo'] }}]))
                  .and_return(criteria)

          Document.filter_by('tags.all' => 'flamengo', 'or' => '[{"names.all": ["basquete"]}, {"names.all" : ["jabulani"]}]')
        end
      end

      context "when give replace attributes for sorting" do
        it "should use the replace attribute for the outside parameters" do
          Document.filter_by('order_by' => 'fullnames').should == [document, other_document]
        end

        it "should use the replace attribute for the outside parameters with modifiers" do
          Document.filter_by('order_by' => 'fullnames.desc').should == [other_document, document]
        end

        it "should use the replace attribute for the default sorting parameters with modifiers" do
          Document.filter_by('tags.all' => 'flamengo').should == [other_document, document]
        end
      end
    end

    describe "when filtering fields" do
      describe "with only" do
        it "should only return the specified fields" do
          document = Document.filter_by('only' => 'title|_id').first
          document.attributes.should == {"_id" => document.id, "title" => document.title}
        end
      end

      describe "with except" do
        it "should return the all fields except the specified fields" do
          document = Document.filter_by('except' => 'title').first
          document.attributes.should == document.reload.attributes.except('title')
        end
      end
    end
  end

  describe 'when returning paginated collection' do
    it 'should return a paginated collection' do
      Document.paginated_collection_with_filter_by.should == {:total_entries => 2, :total_pages => 1, :per_page => 12, :offset => 0, :previous_page => nil, :current_page => 1, :next_page => nil}
    end

    it 'should accept filtering options' do
      context = mock('context', :count => 1)
      Document.should_receive(:where).with({'status' => 'published', 'title' => document.title}).and_return(context)
      Document.paginated_collection_with_filter_by(:title => document.title).should == {:total_entries => 1, :total_pages => 1, :per_page => 12, :offset => 0, :previous_page => nil, :current_page => 1, :next_page => nil}
    end

    it 'should use pagination options' do
      context = mock('context', :count => 100)
      Document.should_receive(:where).with({'status' => 'published'}).and_return(context)
      Document.paginated_collection_with_filter_by(:page => 3, :per_page => 20).should == {:total_entries => 100, :total_pages => 5, :per_page => 20, :offset => 40, :previous_page => 2, :current_page => 3, :next_page => 4}
    end
  end

  describe "results with pager" do
    let(:collection) do
      [Document.new, Document.new, Document.new]
    end

    let(:options)  { {:per_page => per_page, :page => page} }

    let(:per_page) { 3 }
    let(:page)     { 2 }
    let(:total)    { 8 }

    it "should return a pager" do
      Document.paginatable_collection_from(collection, total, options)[:pager].should == {
        :total_entries => 8,
        :total_pages   => 3,
        :per_page      => 3,
        :offset        => 3,
        :previous_page => 1,
        :current_page  => 2,
        :next_page     => 3
      }
    end

    it "should return the results, using the model name as the key, as a paginatable collection" do
      paginatable_collection = WillPaginate::Collection.create page, per_page, total do |pager|
        pager.replace(collection)
      end
      Document.paginatable_collection_from(collection, total, options)[:documents].should == paginatable_collection
    end
  end
end
