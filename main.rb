require 'bundler/setup'

require 'ffi'

module ObjC
  # Basic low-level FFI bindings for Objective-C
  module FFI
    extend ::FFI::Library
    ffi_lib '/usr/lib/libobjc.A.dylib'

    typedef :pointer, :id
    typedef :pointer, :method
    typedef :pointer, :selector

    attach_function :class_getInstanceMethod, [:id, :selector], :method
    attach_function :class_respondsToSelector, [:id, :selector], :bool
    attach_function :method_getArgumentType, [:method, :uint, :pointer, :size_t], :void
    attach_function :method_getNumberOfArguments, [:method], :uint
    attach_function :method_getReturnType, [:method, :pointer, :size_t], :void
    attach_function :objc_getClass, [:string], :id
    attach_function :objc_msgSend, [:pointer, :selector, :varargs], :pointer
    attach_function :object_getClass, [:id], :id
    attach_function :sel_getUid, [:string], :selector
  end

  class Object < ::FFI::Pointer
    def method_missing(method_name, *arguments)
      potential_selectors = [method_name.to_s, "#{method_name}:"]
      selector = nil
      potential_selectors.each do |name|
        candidate = FFI.sel_getUid(name)
        next unless FFI.class_respondsToSelector(objc_class, candidate)

        selector = candidate
        break
      end
      super unless selector

      define_singleton_method(method_name) do |*args|
        return_type_signature, argument_signatures = signature_for_selector(selector)
        msgSend_arguments = argument_signatures.zip(arguments).flatten
        puts "#{self.inspect} -> #{method_name}(#{argument_signatures}) #{return_type_signature} -> #{msgSend_arguments}"
        result = FFI.objc_msgSend(self, selector, *msgSend_arguments)
        result && result.null? ? nil : coerce_return_value(result, return_type_signature)
      end

      send(method_name, *arguments)
    end

    def inspect
      # Implement directly to avoid infinite recursion
      return_value = FFI.objc_msgSend(
        FFI.objc_msgSend(self, FFI.sel_getUid('description')),
        FFI.sel_getUid('UTF8String')
      )
      return_value.read_string
    end

    def objc_class
      @objc_class ||= Object.new(FFI.object_getClass(self))
    end

    private

    def signature_for_selector(selector)
      type_buffer = ::FFI::MemoryPointer.new(:char, 32)
      method = FFI.class_getInstanceMethod(objc_class, selector)
      FFI.method_getReturnType(method, type_buffer, type_buffer.size)
      return_type = type_buffer.read_string
      # the first 2 arguments are always the receiver and the selector - don't care about those
      arguments =  (2...FFI.method_getNumberOfArguments(method)).map { |index|
        FFI.method_getArgumentType(method, index, type_buffer, type_buffer.size)
        objc_signature_to_ffi_type(type_buffer.read_string)
      }

      [return_type, arguments]
    end

    def objc_signature_to_ffi_type(signature)
      case signature
      when '@','#',':' then :pointer
      when '*', 'r*' then :string
      when 'c'  then :char
      when 'C'  then :uchar
      when 's'  then :short
      when 'S'  then :ushort
      when 'i'  then :int
      when 'I'  then :uint
      when 'l'  then :long
      when 'L'  then :ulong
      when 'q'  then :long_long
      when 'Q'  then :ulong_long
      when 'f'  then :float
      when 'd'  then :double
      else
        raise "unhandled argument type #{signature}"
      end
    end

    def coerce_return_value pointer, return_type
      case return_type
      when '@' then Object.new(pointer)
      when 'v' then nil
      when '*', 'r*' then pointer.read_string
      when 'c', 'C', 's', 'S', 'i', 'I', 'l', 'L', 'q', 'Q'
        repack(pointer.address, return_type)
      else
        pointer
      end
    end

    def repack(raw, format)
      [raw].pack('Q').unpack(format).first
    end
  end

  class << self
    def import_library(name)
      FFI.ffi_lib name
    end

    def const_missing(name)
      objc_class = FFI.objc_getClass(name.to_s)
      if objc_class.null?
        super
      else
        const_set(name, Object.new(objc_class))
      end
    end
  end
end

module ObjC
  import_library '/System/Library/Frameworks/AppKit.framework/AppKit'
end

p ObjC::NSApplication.sharedApplication
