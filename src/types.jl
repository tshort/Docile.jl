# Lazy-loading documentation object. Initially the raw documentation string is stored in
# `data` while `obj` field remains undefined. The parsed documentation AST/object/etc. is
# cached in `obj` on first request for it. `format` is a symbol.
type Docs{format}
    data :: String
    obj
    
    # `Lazy `obj` field access which leaves the `obj` field undefined until first accessed.
    Docs(data::String) = new(data)
    
    # Pass `Doc` objects straight through. Simplifies code in `Entry` constructors.
    Docs(docs::Docs) = docs
end

# Guess doc format from file extension. Entry docstring created when file does not exist.
function externaldocs(mod, meta)
    file = abspath(joinpath(getdoc(mod).meta[:root]), get(meta, :file, ""))
    isfile(file) ? readdocs(file) : Docs{getdoc(mod).meta[:format]}("")
end

# Load and apply format based on extension to the given `filename`.
readdocs(file) = Docs{format(file)}(readall(file))

# Extract the format of a file based *solely* of the file's extension.
format(file) = symbol(splitext(file)[end][2:end])

@docref () -> REF_ENTRY
type Entry{category} # category::Symbol
    docs    :: Docs
    meta    :: Dict{Symbol, Any}
    modname :: Module

    function Entry(modname::Module, source, doc, meta::Dict = Dict())
        meta[:source] = source
        new(Docs{getdoc(modname).meta[:format]}(doc), meta, modname)
    end
    
    # No docstring was provided, try to read from :file. Blank docs field when no file.
    function Entry(modname::Module, source, meta::Dict = Dict())
        meta[:source] = source
        new(externaldocs(modname, meta), meta, modname)
    end

    Entry(args...) = error("@doc: incorrect arguments given to macro:\n$(args)")
end

@docref () -> REF_PAGE
type Page
    docs :: Docs
    file :: String
    
    Page(file) = new(readdocs(file), file)
end

@docref () -> REF_MANUAL
type Manual
    pages :: Vector{Page}
    
    Manual(root, files) = new([Page(abspath(joinpath(root, file))) for file in files])
end

# Usage from REPL, use current directory as root.
Manual(::Nothing, files) = Manual(pwd(), files)

const DEFAULT_METADATA = [
    :manual => String[],
    :format => :md
    ]

@docref () -> REF_DOCUMENTATION
type Documentation
    modname :: Module
    manual  :: Manual
    entries :: Dict{Any, Entry}
    meta    :: Dict{Symbol, Any}
    
    function Documentation(m::Module, file, meta::Dict = Dict())
        meta = merge(DEFAULT_METADATA, meta)
        meta[:root] = dirname(file)
        new(m, Manual(meta[:root], meta[:manual]), Dict{Any, Entry}(), meta)
    end
end

Documentation(m::Module, ::Nothing, meta = Dict()) = Documentation(m, joinpath(pwd(), "_"), meta)

# Warn the author about overwritten metadata.
function pushmeta!(doc::Documentation, object, entry::Entry)
    haskey(doc.entries, object) && warn("Overwriting metadata for `$(doc.modname).$(object)`.")
    doc.entries[object] = entry
    nothing # `setmeta!` doesn't return anything.
end

# Metatdata interface for *single* objects. `args` is the docstring and metadata dict.
function setmeta!(modname, object, category, source, args...)
    pushmeta!(getdoc(modname), object, Entry{category}(modname, source, args...))
end

# For varargs method definitions since they generate multiple method objects. Use the
# *same* Entry object for each object's documentation.
function setmeta!(modname, objects::Set, category, source, args...)
    entry = Entry{category}(modname, source, args...)
    meta = getdoc(modname)
    for object in objects
        pushmeta!(meta, object, entry)
    end
end

# Return the Metadata object stored in a module.
function getdoc(modname)
    isdefined(modname, METADATA) || error("No metadata defined in module $(modname).")
    getfield(modname, METADATA)
end
