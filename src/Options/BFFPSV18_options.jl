"""
    validate_solver_options_and_add_default_values!(options)

Validates that the given solver options are supported and adds default values for most
unspecified options.

### Input

- `options` -- an `Options` object, a dictionary of options

Supported options:

- `:verbosity`     -- controls logging output
- `:logfile`       -- name of a log file
- `:mode`          -- main analysis mode
- `:property`      -- a safety property
- `:T`             -- time horizon; alias `:time_horizon`
- `:partition`     -- block partition; elements are 2D vectors containing the
                      start and end of a block
- `:block_types`   -- short hand to set `:block_types_init` and
                      `:block_types_iter`
- `:block_types_init` -- set type for the approximation of the initial states
                         for each block
- `:block_types_iter` -- set type for the approximation of the states ``X_k``,
                         ``k>0``, for each block
- `:ε`             -- short hand to set `:ε_init` and `:ε_iter`
- `:set_type`      -- short hand to set `:set_type_init` and `:set_type_iter`
- `:ε_init`        -- error bound for the approximation of the initial states
                      (during decomposition)
- `:set_type_init` -- set type for the approximation of the initial states
                      (during decomposition)
- `:ε_iter`        -- error bound for the approximation of the states ``X_k``,
                      ``k>0``
- `:set_type_iter` -- set type for the approximation of the states ``X_k``,
                      ``k>0``
- `:ε_proj`        -- error bound for the approximation of the states during
                      projection
- `:set_type_proj` -- set type for the approximation of the states during
                      projection
- `:lazy_expm`     -- switch for using lazy matrix exponential all the time
- `:assume_sparse` -- switch for sparse matrices
- `:pade_expm`     -- switch for using Pade approximant method
- `:lazy_X0`       -- switch for keeping the initial states a lazy set
- `:lazy_sih`      -- switch for using a lazy symmetric interval hull during the
                      discretization
- `:template_directions`       -- short hand to set `template_directions_init`
                                  and `template_directions_iter`
- `:template_directions_init`  -- directions to use for the approximation of the
                                  initial states (during decomposition)
- `:template_directions_iter`  -- directions to use for the approximation of the
                                  states ``X_k``, ``k>0``, for each block
- `:coordinate_transformation` -- coordinate transformation method
- `:assume_homogeneous`        -- switch for ignoring inputs
- `:projection_matrix`         -- projection matrix
- `:project_reachset`          -- switch for applying projection
- `:eager_checking`            -- switch for early terminating property checks
- `:lazy_inputs_interval`      -- length of interval in which the inputs are
                                  handled as a lazy set (``-1`` for 'never');
                                  generally may also be a predicate over indices
- `:lazy_expm_discretize`      -- switch to use lazy matrix exponential in the
                                  discretization phase (see also `:lazy_expm`)
- `:max_jumps`     -- maximum number of discrete jumps in a hybrid automaton;
                      `-1` for deactivation
- `:fixpoint_check` -- check for a fixpoint when analyzing a hybrid automaton
- `:clustering`    -- clustering strategy when analyzing a hybrid automaton
- `:plot_vars`     -- variables for projection and plotting;
                      alias: `:output_variables`
- `:n`             -- system's dimension

We add default values for almost all undefined options, i.e., modify the input
options. The benefit is that the user can print the options that were actually
used. For supporting aliases, we create another copy that is actually used where
we only keep those option names that are used internally.
"""
function validate_solver_options_and_add_default_values!(options::Options)::Options
    global LOGGER

    dict = options.dict
    options_copy = Options()
    dict_copy = options_copy.dict

    # first read the verbosity option and set global log level accordingly
    LOGGER = haskey(dict, :verbosity) ?
        configure_logger(dict[:verbosity]) :
        configure_logger()
    check_aliases_and_add_default_value!(dict, dict_copy, [:verbosity], getlevel(LOGGER))
    if haskey(dict, :logfile)
        add_file_logger(dict[:logfile])
        check_aliases!(dict, dict_copy, [:logfile])
    end

    # check for aliases and use default values for unspecified options
    check_aliases_and_add_default_value!(dict, dict_copy, [:mode], "reach")
    check_aliases_and_add_default_value!(dict, dict_copy, [:property], nothing)
    check_aliases_and_add_default_value!(dict, dict_copy, [:lazy_expm], false)
    check_aliases_and_add_default_value!(dict, dict_copy, [:assume_sparse], false)
    check_aliases_and_add_default_value!(dict, dict_copy, [:pade_expm], false)
    check_aliases_and_add_default_value!(dict, dict_copy, [:lazy_X0], false)
    check_aliases_and_add_default_value!(dict, dict_copy, [:lazy_sih], false)
    check_aliases_and_add_default_value!(dict, dict_copy, [:coordinate_transformation], "")
    check_aliases_and_add_default_value!(dict, dict_copy, [:assume_homogeneous], false)
    check_aliases_and_add_default_value!(dict, dict_copy, [:projection_matrix], nothing)
    check_aliases_and_add_default_value!(dict, dict_copy, [:project_reachset], dict_copy[:projection_matrix] == nothing)
    check_aliases_and_add_default_value!(dict, dict_copy, [:eager_checking], true)
    check_aliases_and_add_default_value!(dict, dict_copy, [:lazy_expm_discretize],
                                         dict_copy[:lazy_expm])
    check_aliases_and_add_default_value!(dict, dict_copy, [:max_jumps], -1)
    check_aliases_and_add_default_value!(dict, dict_copy, [:clustering], :chull)
    check_aliases_and_add_default_value!(dict, dict_copy, [:fixpoint_check], :eager)
    check_aliases_and_add_default_value!(dict, dict_copy, [:n], nothing)
    check_aliases_and_add_default_value!(dict, dict_copy, [:transformation_matrix], nothing)
    check_aliases_and_add_default_value!(dict, dict_copy, [:plot_vars, :output_variables], [0, 1])

    # special option: T
    check_aliases!(dict, dict_copy, [:T, :time_horizon])

    # special options: ε, ε_init, ε_iter, ε_proj,
    #                  set_type, set_type_init, set_type_iter, set_type_proj,
    #                  template_directions, template_directions_init,
    #                  template_directions_iter
    check_and_add_approximation!(dict, dict_copy)

    # special options: partition, block_types, block_types_init, block_types_iter
    check_and_add_partition_block_types!(dict, dict_copy)

    # special option: lazy_inputs_interval
    check_and_add_lazy_inputs_interval!(dict, dict_copy)

    # validate that all input keywords are recognized
    check_valid_option_keywords(dict)

    # validation
    for kv_pair in dict_copy
        key::Symbol = kv_pair.first
        value = kv_pair.second

        # define type/domain constraints for each known key
        domain_constraints = (v  ->  true)
        if key == :verbosity
            expected_type = Union{String, Int}
        elseif key == :logfile
            expected_type = String
        elseif key == :mode
            expected_type = String
            domain_constraints = (v::String  ->  v in ["reach", "check"])
            if value == "check" && dict_copy[:property] == nothing
                error("No property has been defined.")
            end
        elseif key == :property
            expected_type = Union{Property, Nothing}
        elseif key == :T
            expected_type = Float64
            domain_constraints = (v::Float64  ->  v > 0.)
        elseif key == :partition
            expected_type = AbstractVector{<:AbstractVector{Int}}
        elseif key == :block_types
            expected_type = Union{Nothing,
                Dict{Type{<:LazySet}, AbstractVector{<:AbstractVector{Int}}}}
        elseif key == :block_types_init
            expected_type =
                Dict{Type{<:LazySet}, AbstractVector{<:AbstractVector{Int}}}
        elseif key == :block_types_iter
            expected_type =
                Dict{Type{<:LazySet}, AbstractVector{<:AbstractVector{Int}}}
        elseif key == :ε
            expected_type = Float64
            domain_constraints = (v  ->  v > 0.)
        elseif key == :ε_init
            expected_type = Float64
            domain_constraints = (v  ->  v > 0.)
        elseif key == :ε_iter
            expected_type = Float64
            domain_constraints = (v  ->  v > 0.)
        elseif key == :ε_proj
            expected_type = Float64
            domain_constraints = (v  ->  v > 0.)
        elseif key == :set_type
            expected_type = Union{Type{HPolygon}, Type{Hyperrectangle},
                                  Type{LazySets.Interval}}
        elseif key == :set_type_init
            expected_type = Union{Type{HPolygon}, Type{Hyperrectangle},
                                  Type{LazySets.Interval}}
        elseif key == :set_type_iter
            expected_type = Union{Type{HPolygon}, Type{Hyperrectangle},
                                  Type{LazySets.Interval}}
        elseif key == :set_type_proj
            expected_type = Union{Type{HPolygon}, Type{Hyperrectangle},
                                  Type{LazySets.Interval}}
        elseif key == :lazy_expm
            expected_type = Bool
        elseif key == :assume_sparse
            expected_type = Bool
        elseif key == :pade_expm
            expected_type = Bool
        elseif key == :lazy_X0
            expected_type = Bool
        elseif key == :lazy_sih
            expected_type = Bool
        elseif key == :template_directions
            expected_type = Symbol
            domain_constraints = (v::Symbol  ->  v in [:box, :oct, :boxdiag,
                                                       :nothing])
        elseif key == :template_directions_init
            expected_type = Symbol
            domain_constraints = (v::Symbol  ->  v in [:box, :oct, :boxdiag,
                                                       :nothing])
        elseif key == :template_directions_iter
            expected_type = Symbol
            domain_constraints = (v::Symbol  ->  v in [:box, :oct, :boxdiag,
                                                       :nothing])
        elseif key == :coordinate_transformation
            expected_type = String
            domain_constraints = (v::String  ->  v in ["", "schur"])
        elseif key == :assume_homogeneous
            expected_type = Bool
        elseif key == :projection_matrix
            expected_type = Union{AbstractMatrix, Nothing}
        elseif key == :project_reachset
            expected_type = Bool
        elseif key == :eager_checking
            expected_type = Bool
        elseif key == :lazy_inputs_interval
            expected_type = Union{Int, Function, Nothing}
            domain_constraints = (v  ->  !(v isa Int) || v >= -1)
        elseif key == :lazy_expm_discretize
            expected_type = Bool
            if !value && dict_copy[:lazy_expm]
                error("cannot use option $(:lazy_expm) with deactivated " *
                      "option $(:lazy_expm_discretize)")
            end
        elseif key == :max_jumps
            expected_type = Int
            domain_constraints = (v::Int  ->  v >= -1)
        elseif key == :fixpoint_check
            expected_type = Symbol
            domain_constraints = (v::Symbol  ->  v in [:none, :eager, :lazy])
        elseif key == :clustering
            expected_type = Symbol
            domain_constraints = (v::Symbol  ->  v in [:chull, :none])
        elseif key == :plot_vars
            expected_type = Vector{Int}
            domain_constraints = (v::Vector{Int}  ->  length(v) == 2)
        elseif key == :n
            expected_type = Int
            domain_constraints = (v::Int  ->  v > 0)
        elseif key == :transformation_matrix
            expected_type = Any
        else
            error(get_unrecognized_key_message(key))
        end

        # check value type
        if !(value isa expected_type)
            error("Option :$key must be of '$expected_type' type.")
        end
        # check value domain constraints
        if !domain_constraints(value)
            error("$value is not a valid value for option :$key.")
        end
    end

    return options_copy
end

"""
    check_and_add_approximation!(dict::Dict{Symbol,Any},
                                 dict_copy::Dict{Symbol,Any})

Handling of the special options `:ε` and `:set_type` resp. the subcases
`:ε_init`, `:ε_iter`, `:ε_proj`, `:set_type_init`, `:set_type_iter`,
`:set_type_proj`, `:template_directions`, `:template_directions_init`, and
`:template_directions_iter`.

### Input

- `dict`      -- dictionary of options
- `dict_copy` -- copy of the dictionary of options for internal names

### Notes:

`:ε` and `:set_type`, if defined, are used as fallbacks (if the more specific
options are undefined).
If both `:ε_init` and `:set_type_init` are defined, they must be consistent.
"""
function check_and_add_approximation!(dict::Dict{Symbol,Any},
                                      dict_copy::Dict{Symbol,Any})
    # fallback options
    check_aliases!(dict, dict_copy, [:ε])
    check_aliases!(dict, dict_copy, [:set_type])
    check_aliases!(dict, dict_copy, [:template_directions])
    ε = haskey(dict, :ε) ? dict[:ε] : Inf

    # fallback set type
    if haskey(dict, :set_type)
        # use the provided set type
        set_type = dict[:set_type]
    elseif ε < Inf
        # use polygons
        set_type = HPolygon
    elseif !haskey(dict, :partition)
        # use intervals
        set_type = Interval
        set_type_proj = Interval
    else
        # use hyperrectangles
        set_type = Hyperrectangle
    end

    ε_init = (haskey(dict, :set_type_init) && dict[:set_type_init] == HPolygon) ||
             (!haskey(dict, :set_type_init) && set_type == HPolygon) ? ε : Inf
    check_aliases_and_add_default_value!(dict, dict_copy, [:ε_init], ε_init)

    set_type_init = dict_copy[:ε_init] < Inf ? HPolygon : set_type
    check_aliases_and_add_default_value!(dict, dict_copy, [:set_type_init], set_type_init)

    template_directions_init = haskey(dict, :template_directions_init) ?
        dict[:template_directions_init] : haskey(dict, :template_directions) ?
        dict[:template_directions] : :nothing
    check_aliases_and_add_default_value!(dict, dict_copy,
        [:template_directions_init], template_directions_init)

    ε_iter = (haskey(dict, :set_type_iter) && dict[:set_type_iter] == HPolygon) ||
             (!haskey(dict, :set_type_iter) && set_type == HPolygon) ? ε : Inf
    check_aliases_and_add_default_value!(dict, dict_copy, [:ε_iter], ε_iter)

    set_type_iter = dict_copy[:ε_iter] < Inf ? HPolygon : set_type
    check_aliases_and_add_default_value!(dict, dict_copy, [:set_type_iter], set_type_iter)

    template_directions_iter = haskey(dict, :template_directions_iter) ?
        dict[:template_directions_iter] : haskey(dict, :template_directions) ?
        dict[:template_directions] : :nothing
    check_aliases_and_add_default_value!(dict, dict_copy,
        [:template_directions_iter], template_directions_iter)

    ε_proj = (haskey(dict, :set_type_proj) && dict[:set_type_proj] == HPolygon) ||
             (!haskey(dict, :set_type_proj) && set_type == HPolygon) ? ε :
             min(dict_copy[:ε_init], dict_copy[:ε_iter], ε)
    check_aliases_and_add_default_value!(dict, dict_copy, [:ε_proj], ε_proj)

    set_type_proj = dict_copy[:ε_proj] < Inf ? HPolygon : Hyperrectangle
    check_aliases_and_add_default_value!(dict, dict_copy, [:set_type_proj], set_type_proj)

    @assert (dict_copy[:ε_init] == Inf || dict_copy[:set_type_init] == HPolygon) &&
        (dict_copy[:ε_iter] == Inf || dict_copy[:set_type_iter] == HPolygon) &&
        (dict_copy[:ε_proj] == Inf || dict_copy[:set_type_proj] == HPolygon) (
            "ε-close approximation is only supported with the HPolygon set type")
end

"""
    check_and_add_partition_block_types!(dict::Dict{Symbol,Any},
                                         dict_copy::Dict{Symbol,Any})

Handling of the special options `:partition` and `:block_types` resp. the
subcases `:block_types_init` and `:block_types_iter`.

### Input

- `dict`      -- dictionary of options
- `dict_copy` -- copy of the dictionary of options for internal names
"""
function check_and_add_partition_block_types!(dict::Dict{Symbol,Any},
                                              dict_copy::Dict{Symbol,Any})
    check_aliases!(dict, dict_copy, [:partition])
    if !haskey(dict_copy, :partition)
        partition = [[i] for i in 1:dict[:n]]
        dict_copy[:partition] =  partition
    end

    block_types = nothing
    if haskey(dict, :block_types)
        for (key, value) in dict[:block_types]
            @assert key <: LazySet "the keys of the `partition` dictionary should be lazy sets"
            @assert typeof(value) <: AbstractVector{<:AbstractVector{Int}} "the keys of the `partition` dictionary should be vectors of vectors"
        end
        block_types = convert(Dict{Type{<:LazySet}, AbstractVector{<:AbstractVector{Int}}}, dict[:block_types])
    elseif haskey(dict, :set_type)
        block_types = Dict{Type{<:LazySet}, AbstractVector{<:AbstractVector{Int}}}(dict[:set_type] => copy(dict_copy[:partition]))
    end
    check_aliases_and_add_default_value!(dict, dict_copy, [:block_types], block_types)
    dict_copy[:block_types] = block_types

    block_types_init = haskey(dict, :block_types_init) ?
        dict[:block_types_init] :
        block_types != nothing ? block_types :
            Dict{Type{<:LazySet}, AbstractVector{<:AbstractVector{Int}}}(
                dict_copy[:set_type_init] => copy(dict_copy[:partition])
            )
    check_aliases_and_add_default_value!(dict, dict_copy, [:block_types_init],
                                         block_types_init)

    block_types_iter = haskey(dict, :block_types_iter) ?
        dict[:block_types_iter] :
        block_types != nothing ? block_types :
            Dict{Type{<:LazySet}, AbstractVector{<:AbstractVector{Int}}}(
                dict_copy[:set_type_iter] => copy(dict_copy[:partition])
            )
    check_aliases_and_add_default_value!(dict, dict_copy, [:block_types_iter],
                                         block_types_iter)

    # TODO add check that arguments are consistent
end

"""
    check_and_add_lazy_inputs_interval!(dict::Dict{Symbol,Any},
                                        dict_copy::Dict{Symbol,Any})

Handling of the special option `:lazy_inputs_interval`.

### Input

- `dict`      -- dictionary of options
- `dict_copy` -- copy of the dictionary of options for internal names

### Notes

Originally, this option was used to overapproximate a lazy set of inputs at
every multiple of ``k`` steps, where ``k`` was the controllable option; hence
the term `interval` in the name.
Meanwhile, this option was generalized to a predicate over integers.
The predicate returns `true` iff the lazy set should be overapproximated.
However, we still support index numbers as input, which are then translated into
a predicate.

The default value for this option is `nothing` or the index ``0``, which results
in overapproximation in each iteration.
Note that internally this has a different effect than passing the predicate that
always returns `true` because functions cannot be checked for equality.
Thus this option should simply not be set when not wanting this behavior (or the
value ``0`` should be used).

The input ``-1`` is interpreted as the predicate that always returns `false`.
"""
function check_and_add_lazy_inputs_interval!(dict::Dict{Symbol,Any},
                                             dict_copy::Dict{Symbol,Any})
    check_aliases!(dict, dict_copy, [:lazy_inputs_interval])
    if haskey(dict_copy, :lazy_inputs_interval)
        if dict_copy[:lazy_inputs_interval] == -1
            dict_copy[:lazy_inputs_interval] = (k -> false)
        elseif dict_copy[:lazy_inputs_interval] == 0
            dict_copy[:lazy_inputs_interval] = nothing
        elseif dict_copy[:lazy_inputs_interval] isa Int
            m = dict_copy[:lazy_inputs_interval]
            dict_copy[:lazy_inputs_interval] = (k -> k % m == 0)
        end
    else
        dict_copy[:lazy_inputs_interval] = nothing
    end
end
