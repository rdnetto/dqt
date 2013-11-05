module dqt.smoke.smokeqt_loader;

import std.algorithm;
import std.array;
import std.typecons;
import std.stdio;

import dqt.smoke.smoke;
import dqt.smoke.smoke_util;
import dqt.smoke.smoke_cwrapper;

// These functions are very general, and belong elsewhere.
pure @system nothrow
private inout(char)[] toSlice(inout(char)* cString) {
    import std.c.string;

    return cString == null ? null : cString[0 .. strlen(cString)];
}

pure @safe nothrow
private bool isEmptyString(inout(char*) cString) {
    return cString == null || cString[0] == '\0';
}

pure @safe nothrow
private ref V1 setDefault(K, V1, V2)(ref V1[K] map, K key, lazy V2 def)
if (is(V2 : V1)) {
    V1* valPtr = key in map;

    if (valPtr != null) {
        return *valPtr;
    }

    map[key] = def();

    return map[key];
}

struct MethodFunctor {
private:
    const Smoke.ClassFn _classFn;
    const Smoke.Method* _method;

    pure @safe nothrow
    this(const Smoke.ClassFn classFn, const Smoke.Method* method) {
        _classFn = classFn;
        _method = method;
    }
public:
    @property pure @safe nothrow
    public bool isNull() const {
        return _classFn is null;
    }

    @property pure @safe nothrow
    const(Smoke.Method*) method() const
    in {
        assert(!isNull);
    } body {
        return _method;
    }

    Smoke.StackItem opCall(A...)(A a) if (is(A[0] : void*))
    in {
        assert(!method.isInstance || a[0] !is null,
            "null pointer for smoke object, expected instance pointer!");
        assert(a.length - 1 == method.numArgs,
            "Stack size did not match argument count!");
    } body {
        auto stack = createSmokeStack(a[1 .. $]);

        // Forward the call to the C wrapper.
        dqt_call_ClassFn(_classFn, _method.method, a[0], stack.ptr);

        if (method.isConstructor) {
            // Smoke requires an extra call to make constructors work.
            dqt_bind_instance(_classFn, stack[0].s_voidp);
        }

        return stack[0];
    }
}

final class ClassData {
private:
    const(Smoke*) _smoke;
    const(Smoke.Class*) _cls;
    // We'll pack some methods in here, which may have many overloads.
    const(Smoke.Method*)[][string] _overloadedMethodMap;

    pure @safe nothrow
    this(const(Smoke*) smoke, const(Smoke.Class*) cls)
    in {
        assert(smoke !is null);
        assert(cls !is null);
    } body {
        _smoke = smoke;
        _cls = cls;
    }

    pure @safe nothrow
    void addMethod(string methodName, const(Smoke.Method*) method) {
        _overloadedMethodMap.setDefault(methodName, null) ~= method;
    }

    pure @safe nothrow
    const(Smoke.Method*)[] methodMatches(string methodName) {
        auto ptr = methodName in _overloadedMethodMap;

        return ptr !is null ? *ptr : null;
    }
public:
    pure @trusted
    MethodFunctor findMethod(string methodName, string[] argumentTypes ...) {
        import std.c.string;

        methLoop: foreach(meth; methodMatches(methodName)) {
            if (meth.numArgs != argumentTypes.length) {
                continue;
            }

            debug {
                writeln("Possible method match...");
                writeln(methodName);
            }

            // Slice the argument index list out.
            auto argIndexList = _smoke._argumentList[
                meth.args .. meth.args + meth.numArgs];

            foreach(i, argIndex; argIndexList) {
                // Skip to the type pointer.
                auto type = _smoke._types + argIndex;

                debug {
                    writefln("Type name: %s", type.name.toSlice);
                }

                // TODO: Include const and & here?

                if (strcmp(argumentTypes[i].ptr, type.name)) {
                    continue methLoop;
                }
            }

            return MethodFunctor(_cls.classFn, meth);
        }

        return MethodFunctor.init;
    }


    pure @trusted
    MethodFunctor demandMethod(string methodName, string[] argumentTypes ...) {
        import std.exception;

        MethodFunctor functor = findMethod(methodName, argumentTypes);

        enforce(!functor.isNull, "Demanded method not found!");

        return functor;
    }
}

enum QtLibraryFlag : uint {
    qtcore = 0x1,
    qtgui  = 0x2,
    all    = uint.max
}

struct SmokeLoader {
private:
    ClassData[string] _classMap;
    QtLibraryFlag _libraryFlags;

    pure @trusted
    void loadClassMethodData(Smoke* smoke) {
        auto classList = smoke.classList;
        auto methNameList = smoke.methodNameList;

        // Copy out all of the class names up front, we'll need them.
        auto classNameList = classList
        .map!(x => x.className.toSlice.idup)
        .array;

        foreach(const ref meth; smoke.methodList) {
            // TODO: Filter fields and signals out? Are they in there?

            // Smoke "Methods" aren't *just* methods, they can be many things.
            if (meth.name >= methNameList.length
            || meth.classID >= classList.length) {
                continue;
            }

            // Reference our previous copy to get the class name as a string.
            string className = classNameList[meth.classID];

            if (className.length == 0) {
                continue;
            }

            // get/create class data for the class for this method.
            ClassData classData = _classMap.setDefault(className,
                // Skip to the class pointer directly.
                new ClassData(smoke, smoke._classes + meth.classID)
            );

            string methodName = methNameList[meth.name].toSlice.idup;

            classData.addMethod(methodName, &meth);
        }
    }
public:
    @disable this(this);

    @trusted
    this(QtLibraryFlag libraryFlags) {
        _libraryFlags = libraryFlags;

        if (_libraryFlags & QtLibraryFlag.qtcore) {
            dqt_init_qtcore_Smoke();
        }

        if (_libraryFlags & QtLibraryFlag.qtgui) {
            dqt_init_qtgui_Smoke();
        }

        // TODO: We can probably load straight after the init, verify this.
        if (_libraryFlags & QtLibraryFlag.qtcore) {
            loadClassMethodData(cast(Smoke*) dqt_fetch_qtcore_Smoke());
        }

        if (_libraryFlags & QtLibraryFlag.qtgui) {
            loadClassMethodData(cast(Smoke*) dqt_fetch_qtgui_Smoke());
        }
    }

    @trusted
    ~this() {
        if (_libraryFlags & QtLibraryFlag.qtcore) {
            dqt_delete_qtcore_Smoke();
        }

        if (_libraryFlags & QtLibraryFlag.qtgui) {
            dqt_delete_qtgui_Smoke();
        }
    }

    pure @trusted
    ClassData findClass(string className) {
        return _classMap.get(className, null);
    }

    pure @trusted
    ClassData demandClass(string className) {
        import std.exception;

        ClassData cls = findClass(className);

        enforce(cls !is null, "Demanded class not found!");

        return cls;
    }
}

struct QStringHandle {
private:
    void* _ptr;
public:
    @property @safe nothrow
    void* ptr() {
        return _ptr;
    }

    @disable this();
    @disable this(this);

    this(wstring text) {
        _ptr = dqt_init_QString_utf16_reference(
            cast(const(short*)) text.ptr, cast(int) text.length);
    }

    this(string text) {
        _ptr = dqt_init_QString_utf8_copy(text.ptr, cast(int) text.length);
    }

    ~this() {
        dqt_delete_QString(_ptr);
    }
}
