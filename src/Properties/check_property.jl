"""
    check_property(S, N; [algorithm], [ε_init], [set_type_init], [ε_iter],
                   [set_type_iter], [assume_sparse], [assume_homogeneous],
                   [lazy_X0], [kwargs]...)

Interface to property checking algorithms for an LTI system.

### Input

- `S`                  -- LTI system, discrete or continuous
- `N`                  -- number of computed sets
- `algorithm`          -- (optional, default: `"explicit"`), algorithm backend;
                          see `available_algorithms` for all admissible options
- `ε_init`             -- (optional, default: `Inf`) error bound for the
                          approximation of the initial states (during
                          decomposition)
- `set_type_init`      -- (optional, default: `Hyperrectangle`) set type for the
                          approximation of the initial states (during
                          decomposition)
- `ε_iter`             -- (optional, default: `Inf`) error bound for the
                          approximation of the inputs
- `set_type_iter`      -- (optional, default: `Hyperrectangle`) set type for the
                          approximation of the inputs
- `assume_sparse`      -- (optional, default: `true`) if true, it is assumed
                          that the coefficients matrix (exponential) is sparse;
                          otherwise, it is transformed to a full matrix
- `assume_homogeneous` -- (optional, default: `false`) if true, it is assumed
                          that the system has no input (linear system), and it
                          case it has one, the input is ignored
- `lazy_X0`            -- (optional, default: `false`) if true, transform the
                          set of initial states to the caretsian product of
                          two-dimensional polygons; otherwise, the given input,
                          as a lazy set, is passed to the backend
- `kwargs`             -- (optional) additional arguments that are passed to
                          the backend

### Notes

A dictionary with available algorithms is available via
`Properties.available_algorithms`.

WARNING:

Only systems of even dimension are parsed; for odd dimension, manually add an
extra variable with no dynamics.
"""
function check_property(S::AbstractSystem,
                        N::Int;
                        algorithm::String="explicit",
                        ε_init::Float64=Inf,
                        set_type_init::Type{<:LazySet}=Hyperrectangle,
                        ε_iter::Float64=Inf,
                        set_type_iter::Type{<:LazySet}=Hyperrectangle,
                        assume_sparse=true,
                        assume_homogeneous=false,
                        lazy_X0=false,
                        kwargs...)::Int

    # unpack arguments
    kwargs_dict = Dict(kwargs)

    # list containing the arguments passed to any reachability function
    args = []

    # coefficients matrix
    A = S.s.A
    push!(args, A)

    # determine analysis mode (sparse/dense) for lazy_expm mode
    if A isa SparseMatrixExp
        push!(args, Val(assume_sparse))
    end

    n = statedim(S)
    blocks = kwargs_dict[:blocks]
    partition = convert_partition(kwargs_dict[:partition])

    # Cartesian decomposition of the initial set
    info("- Decomposing X0")
    tic()
    if lazy_X0
        Xhat0 = S.x0
    elseif !isempty(kwargs_dict[:block_types_init])
        Xhat0 = array(decompose(S.x0, ɛ=ε_init,
                                block_types=kwargs_dict[:block_types_init]))
    elseif set_type_init == LazySets.Interval
        Xhat0 = array(decompose(S.x0, set_type=set_type_init, ɛ=ε_init,
                                blocks=ones(Int, n)))
    else
        Xhat0 = array(decompose(S.x0, set_type=set_type_init, ɛ=ε_init))
    end
    tocc()

    # shortcut if only the initial set is required
    if N == 1
        if length(blocks) == 1
            Xhat0_mod = Xhat0[blocks[1]]
        else
            Xhat0_mod = CartesianProductArray(Xhat0)
        end
        return check_property(Xhat0_mod, kwargs_dict[:property]) ? 0 : 1
    end
    push!(args, Xhat0)

    # inputs
    if !assume_homogeneous && inputdim(S) > 0
        U = inputset(S)
    else
        U = nothing
    end
    push!(args, U)

    # overapproximation function for states (with/without iterative refinement)
    if haskey(kwargs_dict, :block_types_iter)
        block_types_iter = block_to_set_map(kwargs_dict[:block_types_iter])
        overapproximate_fun = (i, x) -> block_types_iter[i] == HPolygon ?
                              overapproximate(x, HPolygon, ε_iter) :
                              overapproximate(x, block_types_iter[i])
    elseif ε_iter < Inf
        overapproximate_fun =
            (i, x) -> overapproximate(x, set_type_iter, ε_iter)
    else
        overapproximate_fun = (i, x) -> overapproximate(x, set_type_iter)
    end
    push!(args, overapproximate_fun)

    # overapproximate function for inputs
    lazy_inputs_interval = kwargs_dict[:lazy_inputs_interval]
    if lazy_inputs_interval == 0
        overapproximate_inputs_fun = (k, i, x) -> overapproximate_fun(i, x)
    else
        overapproximate_inputs_fun =
            (k, i, x) -> (k % lazy_inputs_interval == 0) ?
                         overapproximate_fun(i, x) :
                         x
    end
    push!(args, overapproximate_inputs_fun)

    # ambient dimension
    push!(args, n)

    # number of computed sets
    push!(args, N)

    # add mode-specific block(s) argument
    if algorithm == "explicit"
        push!(args, blocks)
        push!(args, partition)
        algorithm_backend = "explicit_blocks"
    else
        error("Unsupported algorithm: ", algorithm)
    end

    # add eager/lazy checking option
    push!(args, kwargs_dict[:eager_checking])

    # add property
    push!(args, kwargs_dict[:property])

    # call the adequate function with the given arguments list
    info("- Computing successors")
    tic()
    answer = available_algorithms[algorithm_backend]["func"](args...)
    tocc()

    # return the result
    return answer
end
