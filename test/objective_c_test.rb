require 'minitest/autorun'

require '../lib/objective_c'

module ResetObjectiveCConstants
  extend Minitest::Spec::DSL

  before do
    @original_constants = ObjectiveC.constants.dup
  end

  after do
    (ObjectiveC.constants - @original_constants).each do |const|
      ObjectiveC.send(:remove_const, const)
    end
  end
end

module WithFFIMock
  extend Minitest::Spec::DSL

  let(:ffi) { Minitest::Mock.new }

  before do
    ObjectiveC.ffi = ffi
  end

  after do
    ffi.verify
  end
end

describe ObjectiveC do
  include ResetObjectiveCConstants
  include WithFFIMock

  def build_a_pointer
    FFI::Pointer.new(rand(0xFFFFFFFF))
  end

  let(:null_pointer) { FFI::Pointer.new(0) }

  it 'can dynamically reference classes' do
    ns_string_pointer = build_a_pointer
    ffi.expect :objc_getClass, ns_string_pointer, ['NSString']

    klass = ObjectiveC::NSString

    assert_equal ns_string_pointer, klass
  end

  it 'only loads classes once' do
    ffi.expect :objc_getClass, build_a_pointer, ['NSString']

    first_time = ObjectiveC::NSString
    second_time = ObjectiveC::NSString

    assert_equal second_time, first_time
  end

  it 'raises NameError when a class does not exist' do
    ffi.expect :objc_getClass, null_pointer, ['NonExistentClass']

    assert_raises(NameError) do
      ObjectiveC::NonExistentClass
    end
  end
end
