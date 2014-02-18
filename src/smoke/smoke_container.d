module smoke.smoke_container;

import std.stdio;
import std.array;
import std.exception;

import smoke.smoke;
import smoke.smoke_cwrapper;
import smoke.smoke_util;

@trusted
private long loadEnumValue(Smoke* smoke, Smoke.Method* smokeMethod) pure {
    Smoke.Class* smokeClass = smoke._classes + smokeMethod.classID;

    auto stack = createSmokeStack();

    // Cast this to pure. Sure the data is global, but screw it, make it pure.
    alias extern(C) void function(void*, short, void*, void*) pure PureFunc;

    (cast(PureFunc) &dqt_call_ClassFn)(
        smokeClass.classFn, smokeMethod.method, null, stack.ptr);

    // Get the long value back from the return value of calling a SMOKE
    // function. This is the enum value.
    return stack[0].s_long;
}

@trusted
private string namespaceForName(string name) {
    auto parts = name.split("::");

    if (parts.length > 1) {
        return parts[0 .. $ - 1].join("::");
    }

    return null;
}

/**
 * This class is a D representation of all of the data from a C++ Smoke struct.
 */
class SmokeContainer {
public:
    /**
     * Given a sequence of SMOKE data to load, create a SmokeContainer
     * containing information copied from the SMOKE data.
     */
    static immutable(SmokeContainer) create(Smoke*[] smokeList ...) pure {
        auto container = new SmokeContainer();

        foreach (smoke; smokeList) {
            container.loadData(smoke);
        }

        container.finalize();

        return container;
    }

    /**
     * This class is a D representation of a type in C++, taken from Smoke.
     */
    class Type {
    private:
        string _typeString;
        Smoke.TypeFlags _flags;
        Class _cls;

        @safe pure nothrow
        this(string typeString, Smoke.TypeFlags flags, Class cls) {
            _typeString = typeString;
            _flags = flags;
            _cls = cls;
        }
    public:
        /**
         * Returns: The full string spelling out this type in C++.
         */
        @safe pure nothrow
        @property string typeString() const {
            return _typeString;
        }

        /**
         * Returns: The string spelling out this type in C++, without
         * any qualifiers.
         *
         * Note: 'void*' will be returned as 'void', as will 'void**'
         */
        @safe pure nothrow
        @property string unqualifiedTypeString() const {
            int front = cast(int) this.isConst * 6;
            int end = cast(int) _typeString.length - 1;

            while (_typeString[end] == '*' || _typeString[end] == '&') {
                --end;
            }

            return _typeString[front .. end + 1];
        }

        /**
         * Returns: The class associated with this type, null if no class.
         */
        @safe pure nothrow
        @property const(Class) cls() const {
            return _cls;
        }

        /**
         * Returns: true if this type is a pointer type.
         */
        @safe pure nothrow
        @property bool isPointer() const {
            return (_flags & Smoke.TypeFlags.tf_ptr) != 0;
        }

        /**
         * Returns: The dimensionality of this type is a pointer.
         *
         * T has a dimensionality of 0.
         * T* is 1.
         * T** is 2.
         * T*** is 3.
         */
        @safe pure nothrow
        @property int pointerDimension() const {
            if (!this.isPointer) {
                return 0;
            }

            // Count the pointers by walking backwards in the string.
            // The & qualifier will be on the end if it's a reference.
            int end = cast(int) _typeString.length - 1 - this.isReference;

            while (_typeString[end] == '*') {
                --end;
            }

            return cast(int) _typeString.length - (end + 1 + this.isReference);
        }

        /**
         * Returns: true if this type is a C++ reference type.
         */
        @safe pure nothrow
        @property bool isReference() const {
            return (_flags & Smoke.TypeFlags.tf_ref) != 0;
        }

        /**
         * Returns: true if this type is a C++ const type.
         */
        @safe pure nothrow
        @property bool isConst() const {
            return (_flags & Smoke.TypeFlags.tf_const) != 0;
        }
    }

    /**
     * This class is a representation of a C++ method, taken from Smoke.
     */
    class Method {
    private:
        string _name;
        Class _cls;
        Type _returnType;
        Type[] _argumentTypeList;
        Smoke.MethodFlags _flags;

        @safe pure nothrow
        this() {}
    public:
        /**
         * Returns: The name of this method or function as it is in C++.
         */
        @safe pure nothrow
        @property string name() const {
            return _name;
        }

        /**
         * Returns: The class object for this method. null if no class.
         */
        @safe pure nothrow
        @property const(Class) cls() const {
            return _cls;
        }

        /**
         * Returns: The return type for this method, which may be voidType.
         */
        @safe pure nothrow
        @property const(Type) returnType() const {
            return _returnType;
        }

        /**
         * Returns: The list of argument types for this method,
         *   which may be empty.
         */
        @safe pure nothrow
        @property const(Type[]) argumentTypeList() const {
            return _argumentTypeList;
        }

        /**
         * Returns: True if this method is static.
         */
        @safe pure nothrow
        @property bool isStatic() const {
            return (_flags & Smoke.MethodFlags.mf_static) != 0;
        }

        /**
         * Returns: True if this method is a constructor.
         */
        @safe pure nothrow
        @property bool isConstructor() const {
            return (_flags & Smoke.MethodFlags.mf_ctor) != 0;
        }

        /**
         * Returns: True if this method is a copy constructor.
         */
        @safe pure nothrow
        @property bool isCopyConstructor() const {
            return (_flags & Smoke.MethodFlags.mf_copyctor) != 0;
        }

        /**
         * Returns: True if this method is an explicit constructor.
         */
        @safe pure nothrow
        @property bool isExplicitConstructor() const {
            return (_flags & Smoke.MethodFlags.mf_explicit) != 0;
        }

        /**
         * Returns: True if this method is a destructor.
         */
        @safe pure nothrow
        @property bool isDestructor() const {
            return (_flags & Smoke.MethodFlags.mf_dtor) != 0;
        }

        /**
         * Returns: True if this method is virtual.
         */
        @safe pure nothrow
        @property bool isVirtual() const {
            return (_flags & Smoke.MethodFlags.mf_virtual) != 0;
        }

        /**
         * Returns: True if this method is pure virtual.
         */
        @safe pure nothrow
        @property bool isPureVirtual() const {
            return (_flags & Smoke.MethodFlags.mf_purevirtual) != 0;
        }

        alias isAbstract = isPureVirtual;

        /**
         * Returns: True if this method is a protected method.
         */
        @safe pure nothrow
        @property bool isProtected() const {
            return (_flags & Smoke.MethodFlags.mf_protected) != 0;
        }

        /**
         * Returns: True if this method is const.
         */
        @safe pure nothrow
        @property bool isConst() const {
            return (_flags & Smoke.MethodFlags.mf_const) != 0;
        }

        /**
         * Returns: True if this method is a Qt signal.
         */
        @safe pure nothrow
        @property bool isSignal() const {
            return (_flags & Smoke.MethodFlags.mf_signal) != 0;
        }

        /**
         * Returns: True if this method is a Qt slot.
         */
        @safe pure nothrow
        @property bool isSlot() const {
            return (_flags & Smoke.MethodFlags.mf_slot) != 0;
        }
    }

    /**
     * This class is a representation of a C++ class, taken from Smoke.
     */
    class Class {
    private:
        Class[] _parentClassList;
        string _name;
        Method[] _methodList;
        Class[] _nestedClassList;
        Enum[] _nestedEnumList;

        @safe pure nothrow
        this() {}

        @safe pure nothrow
        this(string name) {
            _name = name;
        }
    public:
        /**
         * A type in C++ can have zero or more parent classes.
         * This is different from D, where every class except Object has
         * only one parent class.
         *
         * Returns: The list of parent classes for this class.
         */
        @safe pure nothrow
        @property const(Class[]) parentClassList() const {
            return _parentClassList;
        }

        /**
         * Returns: A list of classes nested in this class.
         */
        @safe pure nothrow
        @property const(Class[]) nestedClassList() const {
            return _nestedClassList;
        }

        /**
         * Returns: A list of enums nested in this class.
         */
        @safe pure nothrow
        @property const(Enum[]) nestedEnumList() const {
            return _nestedEnumList;
        }

        /**
         * Returns: The name of this class.
         */
        @safe pure nothrow
        @property string name() const {
            return _name;
        }

        /**
         * Returns: The list of methods for this class.
         */
        @safe pure nothrow
        @property const(Method[]) methodList() const {
            return _methodList;
        }
    }

    class Enum {
    public:
        struct Pair {
        private:
            string _name;
            long _value;
        public:
            /**
             * Returns: The name for this enum value.
             */
            @safe pure nothrow
            @property string name() const {
                return _name;
            }

            /**
             * Return: The numerical value for this enum value.
             */
            @safe pure nothrow
            @property long value() const {
                return _value;
            }
        }
    private:
        string _name;
        const(Pair)[] _itemList;

        @safe pure nothrow
        this() {}

        @safe pure nothrow
        this(string name) {
            _name = name;
        }
    public:
        /**
         * Returns: The name of this enum.
         */
        @safe pure nothrow
        @property string name() const {
            return _name;
        }

        /**
         * Returns: A list of pairs for this enum.
         */
        @safe pure nothrow
        @property const(Pair[]) itemList() const {
            return _itemList;
        }
    }

    /**
     * Load data from a Smoke structure. All information will be copied into
     * this container, so the this container is not dependant on the lifetime
     * of the Smoke structure.
     */
    @trusted
    void loadData(Smoke* smoke) pure {
        for (int i = 0; i < smoke._numMethods; ++i) {
            Smoke.Method* smokeMethod = smoke._methods + i;

            if (smokeMethod.flags & Smoke.MethodFlags.mf_enum) {
                // This is an enum value.
                Enum enm = this.getOrCreateEnum(smoke, smokeMethod.ret);

                enm._itemList ~= Enum.Pair(
                    smoke._methodNames[smokeMethod.name].toSlice.idup,
                    loadEnumValue(smoke, smokeMethod)
                );
            } else if (smokeMethod.name >= 0
            && smokeMethod.name < smoke._numMethodNames
            && smokeMethod.classID >= 0
            && smokeMethod.classID < smoke._numClasses) {
                // This is a class method.

                // Get the class for this method, create it if needed.
                Class cls = this.getOrCreateClass(smoke, smokeMethod.classID);

                // Create this method.
                Method method = this.createMethod(cls, smoke, smokeMethod);

                // Add the method to the list of methods in the class.
                cls._methodList ~= method;
            }
        }
    }
private:
    class SmokeMetadata {
        Class[Smoke.Index] _classMap;
        Enum[Smoke.Index] _enumMap;
        Type[Smoke.Index] _typeMap;
    }

    Class[] _topLevelClassList;
    Enum[] _topLevelEnumList;
    SmokeMetadata[Smoke*] _metadataMap;
    bool _finalized;

    @trusted pure
    void loadParentClassesIntoClass
    (Class cls, Smoke* smoke, Smoke.Class* smokeClass) {
        Smoke.Index inheritanceIndex = smokeClass._parents;

        if (inheritanceIndex <= 0) {
            return;
        }

        while (true) {
            Smoke.Index index = smoke._inheritanceList[inheritanceIndex++];

            if (!index) {
                break;
            }

            cls._parentClassList ~= this.getOrCreateClass(smoke, index);
        }
    }

    @safe pure nothrow
    SmokeMetadata getOrCreateMetadata(Smoke* smoke) {
        auto metaPtr = smoke in _metadataMap;

        if (metaPtr) {
            return *metaPtr;
        }

        return _metadataMap[smoke] = new SmokeMetadata();
    }

    @trusted pure
    Class getOrCreateClass(Smoke* smoke, Smoke.Index index) {
        auto metadata = getOrCreateMetadata(smoke);

        Class* ourClassPointer = index in metadata._classMap;

        if (ourClassPointer) {
            return *ourClassPointer;
        }

        Smoke.Class* smokeClass = smoke._classes + index;

        Class cls = metadata._classMap[index] = new Class(
            smokeClass.className.toSlice.idup
        );

        this.loadParentClassesIntoClass(cls, smoke, smokeClass);

        return cls;
    }

    @trusted pure
    Type getOrCreateType(Smoke* smoke, Smoke.Index index) {
        if (index == 0) {
            return new Type("void", cast(Smoke.TypeFlags) 1, null);
        }

        auto metadata = getOrCreateMetadata(smoke);

        Type* ourTypePointer = index in metadata._typeMap;

        if (ourTypePointer) {
            return *ourTypePointer;
        }

        Smoke.Type* smokeType = smoke._types + index;

        return metadata._typeMap[index] = new Type(
            smokeType.name.toSlice.idup,
            cast(Smoke.TypeFlags) smokeType.flags,
            smokeType.classId >= 0
                ? this.getOrCreateClass(smoke, smokeType.classId)
                : null
        );
    }

    @trusted pure
    Enum getOrCreateEnum(Smoke* smoke, Smoke.Index typeIndex) {
        auto metadata = getOrCreateMetadata(smoke);

        Enum* ourEnumPointer = typeIndex in metadata._enumMap;

        if (ourEnumPointer) {
            return *ourEnumPointer;
        }

        Smoke.Type* smokeEnum = smoke._types + typeIndex;

        return metadata._enumMap[typeIndex] = new Enum(
            smokeEnum.name.toSlice.idup
        );
    }

    @trusted pure
    Method createMethod(Class cls, Smoke* smoke, Smoke.Method* smokeMethod) {
        Method method = new Method();

        method._flags = cast(Smoke.MethodFlags) smokeMethod.flags;
        method._name = smoke._methodNames[smokeMethod.name].toSlice.idup;
        method._cls = cls;
        method._returnType = this.getOrCreateType(smoke, smokeMethod.ret);

        if (smokeMethod.numArgs < 1) {
            return method;
        }

        // Load all the argument types into the method object.
        for (int i = 0; i < smokeMethod.numArgs; ++i) {
            Smoke.Index typeIndex = smoke._argumentList[smokeMethod.args + i];

            method._argumentTypeList ~= this.getOrCreateType(smoke, typeIndex);
        }

        return method;
    }

    @safe pure nothrow
    @property bool isFinalized() const {
        return _finalized;
    }

    /**
     * Finalize the Smoke container. This method must be called after loading
     * all of the smoke data required.
     */
    @trusted pure
    void finalize() {
        enforce(!this.isFinalized, "You cannot finalize the container twice!");

        Class[string] namedClassMap;
        Enum[string] namedEnumMap;

        @safe
        bool tryNestInClass(T)(string namespace, T value) {
            Class* contPtr = namespace in namedClassMap;

            if (contPtr) {
                static if (is(T == Class)) {
                    contPtr._nestedClassList ~= value;
                } else static if (is(T == Enum)) {
                    contPtr._nestedEnumList ~= value;
                } else {
                    static assert(false);
                }

                return true;
            }

            return false;
        }

        // Run through everything once to collect it all.
        foreach(_0, metadata; _metadataMap) {
            foreach(_1, cls; metadata._classMap) {
                namedClassMap[cls.name] = cls;
            }

            foreach(_1, enm; metadata._enumMap) {
                namedEnumMap[enm.name] = enm;
            }
        }

        // Now we have everything, run again to build a nested structure.
        foreach(_0, metadata; _metadataMap) {
            foreach(_1, cls; metadata._classMap) {
                string namespace = namespaceForName(cls.name);

                if (namespace.length > 0) {
                    // Nest this class inside a namespace.
                    tryNestInClass(namespace, cls);
                } else {
                    // Put this class at the top level.
                    _topLevelClassList ~= cls;
                }
            }

            foreach(_1, enm; metadata._enumMap) {
                string namespace = namespaceForName(enm.name);

                if (namespace.length > 0) {
                    // Nest this enum inside a namespace.
                    tryNestInClass(namespace, enm);
                } else {
                    // Put this enum at the top level.
                    _topLevelEnumList ~= enm;
                }
            }
        }

        // Throw the metadata at the garbage collector, we're done.
        _metadataMap = null;
        _finalized = true;
    }
public:
    /**
     * Returns: The list of top level classes contained in this container.
     */
    @safe pure
    @property const(Class[]) topLevelClassList() const {
        enforce(this.isFinalized, "Call finalize before accessing this.");

        return _topLevelClassList;
    }

    /**
     * Returns: The list of top level enums contained in this container.
     */
    @safe pure
    @property const(Enum[]) topLevelEnumList() const {
        enforce(this.isFinalized, "Call finalize before accessing this.");

        return _topLevelEnumList;
    }
}