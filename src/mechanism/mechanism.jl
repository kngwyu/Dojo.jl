mutable struct Mechanism{T,Nn,Ne,Nb,Ni}
    origin::Origin{T}
    joints::Vector{<:JointConstraint{T}}
    bodies::Vector{<:Body{T}}
    contacts::Vector{<:ContactConstraint{T}}

    system::System{Nn}
    residual_entries::Vector{Entry}
    matrix_entries::SparseMatrixCSC{Entry,Int64}
    diagonal_inverses::Vector{Entry}

    timestep::T
    gravity::SVector{3,T}
    μ::T
end

function Mechanism(origin::Origin{T}, bodies::Vector{<:Body{T}}, joints::Vector{<:JointConstraint{T}}, contacts::Vector{<:ContactConstraint{T}};
    spring=0.0, damper=0.0, timestep::T=0.01, gravity=[0.0; 0.0;-9.81]) where T

    # reset ids
    resetGlobalID()

    # check body inertia parameters
    check_body.(bodies)

    # dimensions
    Ne = length(joints)
    Nb = length(bodies)
    Ni = length(contacts)
    Nn = Ne + Nb + Ni

    # nodes
    nodes = [joints; bodies; contacts]

    # set ids
    global_id!(nodes)

    # graph system
    system = create_system(origin, joints, bodies, contacts)
    residual_entries = deepcopy(system.vector_entries)
    matrix_entries = deepcopy(system.matrix_entries)
    diagonal_inverses = deepcopy(system.diagonal_inverses)

    # springs and dampers
    joints = set_spring_damper_values!(joints, spring, damper)

    Mechanism{T,Nn,Ne,Nb,Ni}(origin, joints, bodies, contacts, system, residual_entries, matrix_entries, diagonal_inverses, timestep, get_gravity(gravity), 0.0)
end

Mechanism(origin::Origin{T}, bodies::Vector{<:Body{T}}, joints::Vector{<:JointConstraint{T}}; kwargs...) where T = Mechanism(origin, bodies, joints, ContactConstraint{T}[]; kwargs...)

function Mechanism(filename::String, floating::Bool=false, T=Float64; kwargs...)
    # parse urdf
    origin, links, joints, loopjoints = parse_urdf(filename, floating, T)

    # create mechanism
    mechanism = Mechanism(origin, links, [joints; loopjoints]; kwargs...)

    # initialize mechanism
    set_parsed_values!(mechanism, loopjoints)

    return mechanism
end

Base.length(mechanism::Mechanism{T,N}) where {T,N} = N

function residual_dimension(mechanism::Mechanism)
    return sum(Vector{Int}(length.(mechanism.joints))) +
    + sum(Vector{Int}(length.(mechanism.bodies)))
    + sum(Vector{Int}(length.(mechanism.contacts)))
end

# gravity
get_gravity(g::T) where T <: Real = SVector{3,T}([0.0; 0.0; g])
get_gravity(g::Vector{T}) where T = SVector{3,T}(g)
get_gravity(g::SVector) = g
