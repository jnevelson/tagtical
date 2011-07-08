require File.expand_path('../../spec_helper', __FILE__)
describe Tagtical::Taggable do
  before do
    clean_database!
    @taggable = TaggableModel.new(:name => "Bob Jones")
    @taggables = [@taggable, TaggableModel.new(:name => "John Doe")]
  end

  it "should have tag types" do
    TaggableModel.tag_types.should include("tag", "language", "skill", "craft", "need", "offering")
    @taggable.tag_types.should == TaggableModel.tag_types
  end

  it "should have tag_counts_on" do
    TaggableModel.tag_counts_on(:tags).all.should be_empty

    @taggable.tag_list = ["awesome", "epic"]
    @taggable.save

    TaggableModel.tag_counts_on(:tags).length.should == 2
    @taggable.tag_counts_on(:tags).length.should == 2
  end

  it "should be able to create tags" do
    @taggable.skill_list = "ruby, rails, css"
    @taggable.instance_variable_get("@skill_list").should be_an_instance_of(Tagtical::TagList)

    lambda { @taggable.save  }.should change(Tagtical::Tag, :count).by(3)

    @taggable.reload
    @taggable.skill_list.sort.should == %w(ruby rails css).sort
    @taggable.tag_list.sort.should == %w(ruby rails css).sort
  end

  it "should differentiate between contexts" do
    @taggable.skill_list = "ruby, rails, css"
    @taggable.tag_list = "ruby, bob, charlie"
    @taggable.save
    @taggable.reload
    @taggable.skill_list.should include("ruby")
    @taggable.skill_list.should_not include("bob")
  end

  it "should be able to remove tags through list alone" do
    @taggable.skill_list = "ruby, rails, css"
    @taggable.save
    @taggable.reload
    @taggable.should have(3).skills
    @taggable.skill_list = "ruby, rails"
    @taggable.save
    @taggable.reload
    @taggable.should have(2).skills
  end

  it "should be able to select taggables by subset of tags using ActiveRelation methods" do
    @taggables[0].tag_list = "bob"
    @taggables[1].tag_list = "charlie"
    @taggables[0].skill_list = "ruby"
    @taggables[1].skill_list = "css"
    @taggables[0].craft_list = "knitting"
    @taggables[1].craft_list = "pottery"
    @taggables.each(&:save!)

    TaggableModel.tags("bob").should == [@taggables[0]]
    TaggableModel.skills("ruby").should == [@taggables[0]]
    TaggableModel.tags("ruby").should == [@taggables[0]]
    TaggableModel.skills("knitting").should == [@taggables[0]]
    TaggableModel.skills("knitting", :only => :current).should == []
    TaggableModel.skills("knitting", :only => :parents).should == []
    TaggableModel.tags("bob", :only => :current).should == [@taggables[0]]
    TaggableModel.skills("bob", :only => :parents).should == [@taggables[0]]
    TaggableModel.crafts("knitting").should == [@taggables[0]]
    end
  end

  it "should not care about case" do
    bob = TaggableModel.create!(:name => "Bob", :tag_list => "ruby")
    frank = TaggableModel.create!(:name => "Frank", :tag_list => "Ruby")

    Tagtical::Tag.find(:all).size.should == 1
    TaggableModel.tagged_with("ruby").to_a.should == TaggableModel.tagged_with("Ruby").to_a
  end

  it "should be able to get tag counts on model as a whole" do
    bob = TaggableModel.create(:name => "Bob", :tag_list => "ruby, rails, css")
    frank = TaggableModel.create(:name => "Frank", :tag_list => "ruby, rails")
    charlie = TaggableModel.create(:name => "Charlie", :skill_list => "ruby")
    TaggableModel.tag_counts.all.should_not be_empty
    TaggableModel.skill_counts.all.should_not be_empty
  end

  it "should be able to get all tag counts on model as whole" do
    bob = TaggableModel.create(:name => "Bob", :tag_list => "ruby, rails, css")
    frank = TaggableModel.create(:name => "Frank", :tag_list => "ruby, rails")
    charlie = TaggableModel.create(:name => "Charlie", :skill_list => "ruby")

    TaggableModel.all_tag_counts.all.should_not be_empty
    TaggableModel.all_tag_counts(:order => 'tags.id').map { |tag| [tag.class, tag.value, tag.count] }.should == [
      [Tagtical::Tag, "ruby", 2],
      [Tagtical::Tag, "rails", 2],
      [Tagtical::Tag, "css", 1],
      [Tag::Skill, "ruby", 1] ]
  end

  if ActiveRecord::VERSION::MAJOR >= 3
    it "should not return read-only records" do
      TaggableModel.create(:name => "Bob", :tag_list => "ruby, rails, css")
      TaggableModel.tagged_with("ruby").first.should_not be_readonly
    end
  else
    it "should not return read-only records" do
      # apparantly, there is no way to set readonly to false in a scope if joins are made
    end

    it "should be possible to return writable records" do
      TaggableModel.create(:name => "Bob", :tag_list => "ruby, rails, css")
      TaggableModel.tagged_with("ruby").first(:readonly => false).should_not be_readonly
    end
  end

  context "with inheriting tags classes" do
    before do
      @top_level = Tagtical::Tag
      @second_level = Tag::Skill
      @third_level = Tag::Craft
    end

    it "should not create tags on parent if children have the value" do
      lambda {
        @taggable.skill_list = "pottery"
        @taggable.save!
        @taggable.reload
        @taggable.craft_list = "pottery"
        @taggable.save!
       }.should change(Tagtical::Tagging, :count).by(1)

      @taggable.reload
      @taggable.skills.should have(1).item
      @taggable.skills.first.should be_an_instance_of Tag::Craft
    end

  end

  context "with multiple taggable models" do

    before do
      @bob = TaggableModel.create(:name => "Bob", :tag_list => "ruby, rails, css")
      @frank = TaggableModel.create(:name => "Frank", :tag_list => "ruby, rails")
      @charlie = TaggableModel.create(:name => "Charlie", :skill_list => "ruby, java")
    end

    RSpec::Matchers.define :have_tags_counts_of do |expected|
      def breakdown(tags)
        tags.map { |tag| [tag.class, tag.value, tag.count] }
      end
      match do |actual|
        breakdown(actual) == expected
      end
      failure_message_for_should do |actual|
         "expected #{breakdown(actual)} to have the breakdown #{expected}"
      end
    end

    it "should be able to get scoped tag counts" do
      TaggableModel.tagged_with("ruby").tag_counts(:order => 'tags.id').should have_tags_counts_of [
        [Tagtical::Tag, "ruby", 2],
        [Tagtical::Tag, "rails", 2],
        [Tagtical::Tag, "css", 1],
        [Tag::Skill, "ruby", 1],
        [Tag::Skill, "java", 1] ]
      TaggableModel.tagged_with("ruby").skill_counts.first.count.should == 1 # ruby
    end

    it "should be able to get all scoped tag counts" do
      TaggableModel.tagged_with("ruby").all_tag_counts(:order => 'tags.id').should have_tags_counts_of [
        [Tagtical::Tag, "ruby", 2],
        [Tagtical::Tag, "rails", 2],
        [Tagtical::Tag, "css", 1],
        [Tag::Skill, "ruby", 1],
        [Tag::Skill, "java", 1] ]
    end

    it 'should only return tag counts for the available scope' do
      TaggableModel.tagged_with('rails').all_tag_counts.should have_tags_counts_of [
        [Tagtical::Tag, "ruby", 2],
        [Tagtical::Tag, "rails", 2],
        [Tagtical::Tag, "css", 1]]
      TaggableModel.tagged_with('rails').all_tag_counts.any? { |tag| tag.value == 'java' }.should be_false

      # Test specific join syntaxes:
      @frank.untaggable_models.create!
      TaggableModel.tagged_with('rails').scoped(:joins => :untaggable_models).all_tag_counts.should have(2).items
      TaggableModel.tagged_with('rails').scoped(:joins => { :untaggable_models => :taggable_model }).all_tag_counts.should have(2).items
      TaggableModel.tagged_with('rails').scoped(:joins => [:untaggable_models]).all_tag_counts.should have(2).items
    end
  end

  it "should be able to find tagged with quotation marks" do
    bob = TaggableModel.create(:name => "Bob", :tag_list => "fitter, happier, more productive, 'I love the ,comma,'")
    TaggableModel.tagged_with("'I love the ,comma,'").should include(bob)
  end

  it "should be able to find tagged with invalid tags" do
    bob = TaggableModel.create(:name => "Bob", :tag_list => "fitter, happier, more productive")
    TaggableModel.tagged_with("sad, happier").should_not include(bob)
  end

  context "with multiple tag lists per taggable model" do
    before do
      @bob = TaggableModel.create(:name => "Bob", :tag_list => "fitter, happier, more productive", :skill_list => "ruby, rails, css")
      @frank = TaggableModel.create(:name => "Frank", :tag_list => "weaker, depressed, inefficient", :skill_list => "ruby, rails, css")
      @steve = TaggableModel.create(:name => 'Steve', :tag_list => 'fitter, happier, more productive', :skill_list => 'c++, java, ruby')
    end

    it "should be able to find tagged" do
      TaggableModel.tagged_with("ruby", :order => 'taggable_models.name').to_a.should == [@bob, @frank, @steve]
      TaggableModel.tagged_with("ruby, rails", :order => 'taggable_models.name').to_a.should == [@bob, @frank]
      TaggableModel.tagged_with(["ruby", "rails"], :order => 'taggable_models.name').to_a.should == [@bob, @frank]
    end

    it "should be able to find tagged with any tag" do
      TaggableModel.tagged_with(["ruby", "java"], :order => 'taggable_models.name', :any => true).to_a.should == [@bob, @frank, @steve]
      TaggableModel.tagged_with(["c++", "fitter"], :order => 'taggable_models.name', :any => true).to_a.should == [@bob, @steve]
      TaggableModel.tagged_with(["fitter", "css"], :order => 'taggable_models.name', :any => true, :on => :skills).to_a.should == [@bob, @frank]
    end

    it "should be able to use named scopes to chain tag finds" do
      # Let's only find those productive Rails developers
      TaggableModel.tagged_with('rails', :on => :skills, :order => 'taggable_models.name').to_a.should == [@bob, @frank]
      TaggableModel.tagged_with('happier', :on => :tags, :order => 'taggable_models.name').to_a.should == [@bob, @steve]
      TaggableModel.tagged_with('rails', :on => :skills).tagged_with('happier', :on => :tags).to_a.should == [@bob]
      TaggableModel.tagged_with('rails').tagged_with('happier', :on => :tags).to_a.should == [@bob]
    end
  end

  it "should be able to find tagged with only the matching tags" do
    bob = TaggableModel.create(:name => "Bob", :tag_list => "lazy, happier")
    frank = TaggableModel.create(:name => "Frank", :tag_list => "fitter, happier, inefficient")
    steve = TaggableModel.create(:name => 'Steve', :tag_list => "fitter, happier")
    TaggableModel.tagged_with("fitter, happier", :match_all => true).to_a.should == [steve]
  end

  it "should be able to find tagged with some excluded tags" do
    bob = TaggableModel.create(:name => "Bob", :tag_list => "happier, lazy")
    frank = TaggableModel.create(:name => "Frank", :tag_list => "happier")
    steve = TaggableModel.create(:name => 'Steve', :tag_list => "happier")

    TaggableModel.tagged_with("lazy", :exclude => true).to_a.should == [frank, steve]
  end

  it "should not create duplicate taggings" do
    bob = TaggableModel.create(:name => "Bob")
    lambda {
      bob.tag_list << "happier"
      bob.tag_list << "happier"
      bob.save
    }.should change(Tagtical::Tagging, :count).by(1)
  end

  describe "Associations" do
    before(:each) do
      @taggable = TaggableModel.create(:tag_list => "awesome, epic")
    end

    it "should not remove tags when creating associated objects" do
      @taggable.untaggable_models.create!
      @taggable.reload
      @taggable.tag_list.should have(2).items
    end
  end

  describe "grouped_column_names_for method" do
    it "should return all column names joined for Tag GROUP clause" do
      @taggable.grouped_column_names_for(Tagtical::Tag).should == "tags.id, tags.value, tags.type"
    end

    it "should return all column names joined for TaggableModel GROUP clause" do
      @taggable.grouped_column_names_for(TaggableModel).should == "taggable_models.id, taggable_models.name, taggable_models.type"
    end
  end

  describe "Single Table Inheritance for tags" do
    before do
      @taggable = TaggableModel.new(:name => "taggable")
    end

  end

  describe "Single Table Inheritance" do
    before do
      @taggable = TaggableModel.new(:name => "taggable")
      @inherited_same = InheritingTaggableModel.new(:name => "inherited same")
      @inherited_different = AlteredInheritingTaggableModel.new(:name => "inherited different")
    end

    it "should be able to save tags for inherited models" do
      @inherited_same.tag_list = "bob, kelso"
      @inherited_same.save
      InheritingTaggableModel.tagged_with("bob").first.should == @inherited_same
    end

    it "should find STI tagged models on the superclass" do
      @inherited_same.tag_list = "bob, kelso"
      @inherited_same.save
      TaggableModel.tagged_with("bob").first.should == @inherited_same
    end

    it "should be able to add on contexts only to some subclasses" do
      @inherited_different.part_list = "fork, spoon"
      @inherited_different.save
      InheritingTaggableModel.tagged_with("fork", :on => :parts).should be_empty
      AlteredInheritingTaggableModel.tagged_with("fork", :on => :parts).first.should == @inherited_different
    end

    it "should have different tag_counts_on for inherited models" do
      @inherited_same.tag_list = "bob, kelso"
      @inherited_same.save!
      @inherited_different.tag_list = "fork, spoon"
      @inherited_different.save!

      InheritingTaggableModel.tag_counts_on(:tags, :order => 'tags.id').map(&:value).should == %w(bob kelso)
      AlteredInheritingTaggableModel.tag_counts_on(:tags, :order => 'tags.id').map(&:value).should == %w(fork spoon)
      TaggableModel.tag_counts_on(:tags, :order => 'tags.id').map(&:value).should == %w(bob kelso fork spoon)
    end

    it 'should store same tag without validation conflict' do
      @taggable.tag_list = 'one'
      @taggable.save!

      @inherited_same.tag_list = 'one'
      @inherited_same.save!

      @inherited_same.update_attributes! :name => 'foo'
    end
  end

  describe "#owner_tags_on" do
    before do
      @user = TaggableUser.create!
      @user1 = TaggableUser.create!
      @model = TaggableModel.create!(:name => "Bob", :tag_list => "fitter, happier, more productive")
      @user.tag(@model, :with => "martial arts", :on => :skills)
      @user1.tag(@model, :with => "pottery", :on => :crafts)
      @user1.tag(@model, :with => ["spoon", "pottery"], :on => :tags)
    end

    it "should ignore different contexts" do
      @model.owner_tags_on(@user, :languages).should be_empty
    end

    it "should return for only the specified context" do
      @model.owner_tags_on(@user, :skills).should have(1).items

      @model.owner_tags_on(@user, :tags).should have(1).items
      @model.owner_tags_on(@user1, :tags).should have(2).items
    end

    it "should preserve the tag type even though we tag on :tags" do
      @model.tags.find_by_value("pottery").should be_an_instance_of(Tag::Craft)
    end

    it "should support STI" do
      tag = @model.crafts.find_by_value("pottery")
      @model.owner_tags_on(@user1, :crafts).should == [tag]
      @model.owner_tags_on(@user1, :skills).should == [tag]
      @model.owner_tags_on(@user1, :tags).should include(tag)
    end
  end

  it "should be able to set a custom tag context list" do
    bob = TaggableModel.create(:name => "Bob")
    bob.set_tag_list_on(:rotors, "spinning, jumping")
    bob.tag_list_on(:rotors).should == ["spinning","jumping"]
    bob.save
    bob.reload
    bob.tags_on(:rotors).should_not be_empty
  end

  it "should be able to create tags through the tag list directly" do
    @taggable.tag_list_on(:test).add("hello")
    @taggable.tag_list_cache_on(:test).should_not be_empty
    @taggable.tag_list_on(:test).should == ["hello"]

    @taggable.save
    @taggable.save_tags

    @taggable.reload
    @taggable.tag_list_on(:test).should == ["hello"]
  end

  it "should be able to find tagged on a custom tag context" do
    bob = TaggableModel.create(:name => "Bob")
    bob.set_tag_list_on(:rotors, "spinning, jumping")
    bob.tag_list_on(:rotors).should == ["spinning","jumping"]
    bob.save

    TaggableModel.tagged_with("spinning", :on => :rotors).to_a.should == [bob]
  end

end
