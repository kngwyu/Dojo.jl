"""
    NonlinearContact{T,N} <: Contact{T,N}

    contact object for impact and friction with a nonlinear friction cone

    friction_coefficient: value of friction coefficient
    contact_tangent: mapping from world frame to surface tangent frame 
    contact_normal: inverse/complement of contact_tangent
    contact_origin: position of contact on Body relative to center of mass 
    contact radius: radius of contact
"""
mutable struct NonlinearContact{T,N} <: Contact{T,N}
    friction_coefficient::T
    friction_parameterization::SMatrix{2,2,T,4}
    collision::Collision{T,2,3,6}
end

function NonlinearContact(body::Body{T}, normal::AbstractVector, friction_coefficient; 
    contact_origin=szeros(T, 3), 
    contact_radius=0.0) where T

    # contact directions
    V1, V2, V3 = orthogonal_columns(normal)
    A = [V1 V2 V3]
    Ainv = inv(A)
    contact_normal = Ainv[3, SA[1; 2; 3]]'
    contact_tangent = Ainv[SA[1; 2], SA[1; 2; 3]]
    
    # friction parameterization
    parameterization = SA{T}[
         1.0  0.0
         0.0  1.0
    ]

    # collision 
    collision = SphereHalfSpaceCollision(contact_tangent, contact_normal, SVector{3}(contact_origin), contact_radius)
    
    NonlinearContact{T,8}(friction_coefficient, parameterization, collision)
end

function constraint(mechanism, contact::ContactConstraint{T,N,Nc,Cs,N½}) where {T,N,Nc,Cs<:NonlinearContact{T,N},N½}
    # contact model
    model = contact.model

    # parent 
    pbody = get_body(mechanism, contact.parent_id)
    xp, vp, qp, ϕp = next_configuration_velocity(pbody.state, mechanism.timestep)

    # child
    cbody = get_body(mechanism, contact.child_id)
    xc, vc, qc, ϕc = next_configuration_velocity(cbody.state, mechanism.timestep)

    # distance 
    d = distance(model.collision, xp, qp, xc, qc)

    # relative tangential velocity
    vt = relative_tangential_velocity(model, xp, qp, vp, ϕp, xc, qc, vc, ϕc)

    # unpack contact variables 
    γ = contact.impulses[2]
    s = contact.impulses_dual[2]

    SVector{N½,T}(
        d - s[1],
        model.friction_coefficient * γ[1] - γ[2],
        (model.friction_parameterization * vt - s[@SVector [3,4]])...)
end

function constraint_jacobian(contact::ContactConstraint{T,N,Nc,Cs,N½}) where {T,N,Nc,Cs<:NonlinearContact{T,N},N½}
    friction_coefficient = contact.model.friction_coefficient
    γ = contact.impulses[2] + REG * neutral_vector(contact.model) # TODO need to check this is legit
    s = contact.impulses_dual[2] + REG * neutral_vector(contact.model) # TODO need to check this is legit

    ∇s1 = [γ[SA[1]]; szeros(T,3)]'
    ∇s2 = [szeros(T,3,1) cone_product_jacobian(γ[SA[2,3,4]])]
    ∇s3 = Diagonal(SVector{4,T}(-1.0, 0.0, -1.0, -1.0))
    ∇s = [∇s1; ∇s2; ∇s3]

    ∇γ1 = [s[SA[1]]; szeros(T, 3)]'
    ∇γ2 = [szeros(T,3,1) cone_product_jacobian(s[SA[2,3,4]])]
    ∇γ3 = SA[0.0                   0.0 0.0 0.0;
             friction_coefficient -1.0 0.0 0.0;
             0.0                   0.0 0.0 0.0;
             0.0                   0.0 0.0 0.0;]
    ∇γ = [∇γ1; ∇γ2; ∇γ3]

    return [∇s ∇γ]
end

neutral_vector(::NonlinearContact{T,N}) where {T,N} = [sones(T, 2); szeros(T, Int(N/2) - 2)]

cone_degree(::NonlinearContact) = 2
