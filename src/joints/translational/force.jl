## Position level constraints (for dynamics) in world frame
@inline function gc(joint::Translational, xa::AbstractVector, qa::UnitQuaternion, xb::AbstractVector, qb::UnitQuaternion; rotate::Bool = true)
    vertices = joint.vertices
    d = xb + vrotate(vertices[2], qb) - (xa + vrotate(vertices[1], qa))
    rotate && (d = vrotate(d, inv(qa)))
    return d
end
# @inline function gc(joint::Translational, xb::AbstractVector, qb::UnitQuaternion)
#     vertices = joint.vertices
#     return xb + vrotate(vertices[2], qb) - vertices[1]
# end

### Spring and damper
## Forces for dynamics
## Discrete-time position wrappers (for dynamics)
springforcea(joint::Translational, bodya::Component, bodyb::Component, Δt) = Δt * springforcea(joint, posargs2(bodya.state)..., posargs2(bodyb.state)...)
springforceb(joint::Translational, bodya::Component, bodyb::Component, Δt) = Δt * springforceb(joint, posargs2(bodya.state)..., posargs2(bodyb.state)...)
# springforceb(joint::Translational, bodyb::Component, Δt) = Δt * springforceb(joint, posargs2(bodyb.state)...)
damperforcea(joint::Translational, bodya::Component, bodyb::Component, Δt) = Δt * damperforcea(joint, posargs2(bodya.state)..., bodya.state.vsol[2], bodya.state.ϕsol[2], posargs2(bodyb.state)..., bodyb.state.vsol[2], bodyb.state.ϕsol[2])
damperforceb(joint::Translational, bodya::Component, bodyb::Component, Δt) = Δt * damperforceb(joint, posargs2(bodya.state)..., bodya.state.vsol[2], bodya.state.ϕsol[2], posargs2(bodyb.state)..., bodyb.state.vsol[2], bodyb.state.ϕsol[2])
# damperforceb(joint::Translational, bodyb::Component, Δt) = Δt * damperforceb(joint, posargs2(bodyb.state)..., bodyb.state.vsol[2], bodyb.state.ϕsol[2])

springforcea(joint::Translational3{T}, bodya::Component, bodyb::Component, Δt) where {T} = szeros(T, 6)
springforceb(joint::Translational3{T}, bodya::Component, bodyb::Component, Δt) where {T} = szeros(T, 6)
# springforceb(joint::Translational3{T}, bodyb::Component, Δt) where {T} = szeros(T, 6)
damperforcea(joint::Translational3{T}, bodya::Component, bodyb::Component, Δt) where {T} = szeros(T, 6)
damperforceb(joint::Translational3{T}, bodya::Component, bodyb::Component, Δt) where {T} = szeros(T, 6)
# damperforceb(joint::Translational3{T}, bodyb::Component, Δt) where {T} = szeros(T, 6)

# Used in energy computation
springforcea(joint::Translational3{T}, xa::AbstractVector, qa::UnitQuaternion, xb::AbstractVector, qb::UnitQuaternion; rotate::Bool = true) where {T} = szeros(T, 6)
springforceb(joint::Translational3{T}, xa::AbstractVector, qa::UnitQuaternion, xb::AbstractVector, qb::UnitQuaternion; rotate::Bool = true) where {T} = szeros(T, 6)
# springforceb(joint::Translational3{T}, xb::AbstractVector, qb::UnitQuaternion; rotate::Bool = true) where {T} = szeros(T, 6)

### Spring and damper
## Forces for dynamics
# Force applied by body b on body a expressed in world frame
@inline function springforcea(joint::Translational{T}, xa::AbstractVector, qa::UnitQuaternion,
    xb::AbstractVector, qb::UnitQuaternion; rotate::Bool = true) where {T}
    A = nullspacemat(joint)
    Aᵀ = zerodimstaticadjoint(A)
    distance = A * gc(joint, xa, qa, xb, qb) .- joint.spring_offset
    force = joint.spring * Aᵀ * distance # Currently assumes same spring constant in all directions
    forceA = force # in the A frame
    rotate && (force = vrotate(force, qa)) # rotate back to world frame

    torque = skew(joint.vertices[1]) * forceA
    return [force; torque]
end

# Force applied by body a on body b expressed in world frame
@inline function springforceb(joint::Translational{T}, xa::AbstractVector, qa::UnitQuaternion,
        xb::AbstractVector, qb::UnitQuaternion; rotate::Bool = true) where {T}
    A = nullspacemat(joint)
    Aᵀ = zerodimstaticadjoint(A)
    distance = A * gc(joint, xa, qa, xb, qb) .- joint.spring_offset
    force = - joint.spring * Aᵀ * distance  # Currently assumes same spring constant in all directions
    forceA = force
    rotate && (force = vrotate(force, qa)) # rotate back to world frame

    pa_a = rotation_matrix(inv(qa)) * (xa + rotation_matrix(qa) * joint.vertices[1]) # body a kinematics point
    cb_a = rotation_matrix(inv(qa)) * (xb) # body b com
    ra = pa_a - cb_a
    torque = rotation_matrix(inv(qb) * qa) * skew(ra) * forceA
    return [force; torque]
end

# Force applied by origin on body b expressed in world frame
# @inline function springforceb(joint::Translational{T}, xb::AbstractVector, qb::UnitQuaternion) where {T}
#     A = nullspacemat(joint)
#     Aᵀ = zerodimstaticadjoint(A)
#     distance = A * gc(joint, xb, qb) .- joint.spring_offset
#     force = - joint.spring * Aᵀ * distance  # Currently assumes same spring constant in all directions
#     forceA = force

#     pa_a = joint.vertices[1] # body a kinematics point
#     cb_a = xb # body b com
#     ra = pa_a - cb_a
#     torque = rotation_matrix(inv(qb)) * skew(ra) * forceA
#     return [force; torque]
# end

# Force applied by body b on body a expressed in world frame
@inline function damperforcea(joint::Translational{T}, xa::AbstractVector, qa::UnitQuaternion, va::AbstractVector, ωa::AbstractVector,
        xb::AbstractVector, qb::UnitQuaternion, vb::AbstractVector, ωb::AbstractVector; rotate::Bool = true) where {T}
    A = nullspacemat(joint)
    Aᵀ = zerodimstaticadjoint(A)

    pa_b = rotation_matrix(inv(qb)) * (xa + rotation_matrix(qa) * joint.vertices[1]) # body a kinematics point
    cb_b = xb # body b com
    rb = pa_b - cb_b
    vpb = vb + vrotate(skew(ωb) * rb, qb)
    vpa = va + vrotate(skew(ωa) * joint.vertices[1], qa)

    # velocity = A * vrotate(vpb - vpa, inv(qa))
    velocity = A * vrotate(vb - va, inv(qa))
    force = joint.damper * Aᵀ * velocity  # Currently assumes same damper constant in all directions
    forceA = force # in the A frame
    rotate && (force = vrotate(force, qa)) # rotate back to world frame

    torque = skew(joint.vertices[1]) * forceA
    return [force; torque]
end
# Force applied by body a on body b expressed in world frame
@inline function damperforceb(joint::Translational{T}, xa::AbstractVector, qa::UnitQuaternion, va::AbstractVector, ωa::AbstractVector,
        xb::AbstractVector, qb::UnitQuaternion, vb::AbstractVector, ωb::AbstractVector; rotate::Bool = true) where {T}
    A = nullspacemat(joint)
    Aᵀ = zerodimstaticadjoint(A)

    pa_b = rotation_matrix(inv(qb)) * (xa + rotation_matrix(qa) * joint.vertices[1]) # body a kinematics point
    cb_b = xb # body b com
    rb = pa_b - cb_b
    vpb = vb + vrotate(skew(ωb) * rb, qb)
    vpa = va + vrotate(skew(ωa) * joint.vertices[1], qa)

    # velocity = A * vrotate(vpb - vpa, inv(qa))
    velocity = A * vrotate(vb - va, inv(qa))
    force = - joint.damper * Aᵀ * velocity  # Currently assumes same damper constant in all directions
    forceA = force
    rotate && (force = vrotate(force, qa)) # rotate back to world frame

    pa_a = rotation_matrix(inv(qa)) * (xa + rotation_matrix(qa) * joint.vertices[1]) # body a kinematics point
    cb_a = rotation_matrix(inv(qa)) * (xb) # body b com
    ra = pa_a - cb_a
    torque = rotation_matrix(inv(qb) * qa) * skew(ra) * forceA
    return [force; torque]
end

# Force applied by origin on body b expressed in world frame
# @inline function damperforceb(joint::Translational{T}, xb::AbstractVector, qb::UnitQuaternion, vb::AbstractVector, ωb::AbstractVector; rotate::Bool = true) where {T}
#     A = nullspacemat(joint)
#     Aᵀ = zerodimstaticadjoint(A)

#     pa_b = rotation_matrix(inv(qb)) * joint.vertices[1] # body a kinematics point
#     cb_b = xb # body b com
#     rb = pa_b - cb_b
#     vpb = vb + vrotate(skew(ωb) * rb, qb)

#     # velocity = A * vpb
#     velocity = A * vb
#     force = - joint.damper * Aᵀ * velocity  # Currently assumes same damper constant in all directions
#     forceA = force

#     pa_a = joint.vertices[1] # body a kinematics point
#     cb_a = xb # body b com
#     ra = pa_a - cb_a
#     torque = rotation_matrix(inv(qb)) * skew(ra) * forceA
#     return [force; torque]
# end

∂springforcea∂posa(joint::Translational3{T}, body1::Component, body2::Component, Δt::T; attjac::Bool = true) where T = attjac ? szeros(T, 6, 6) : szeros(T, 6, 7)
∂damperforcea∂posa(joint::Translational3{T}, body1::Component, body2::Component, Δt::T; attjac::Bool = true) where T = attjac ? szeros(T, 6, 6) : szeros(T, 6, 7)
∂springforcea∂posb(joint::Translational3{T}, body1::Component, body2::Component, Δt::T; attjac::Bool = true) where T = attjac ? szeros(T, 6, 6) : szeros(T, 6, 7)
∂damperforcea∂posb(joint::Translational3{T}, body1::Component, body2::Component, Δt::T; attjac::Bool = true) where T = attjac ? szeros(T, 6, 6) : szeros(T, 6, 7)
∂springforceb∂posb(joint::Translational3{T}, body1::Component, body2::Component, Δt::T; attjac::Bool = true) where T = attjac ? szeros(T, 6, 6) : szeros(T, 6, 7)
∂damperforceb∂posb(joint::Translational3{T}, body1::Component, body2::Component, Δt::T; attjac::Bool = true) where T = attjac ? szeros(T, 6, 6) : szeros(T, 6, 7)
∂springforceb∂posa(joint::Translational3{T}, body1::Component, body2::Component, Δt::T; attjac::Bool = true) where T = attjac ? szeros(T, 6, 6) : szeros(T, 6, 7)
∂damperforceb∂posa(joint::Translational3{T}, body1::Component, body2::Component, Δt::T; attjac::Bool = true) where T = attjac ? szeros(T, 6, 6) : szeros(T, 6, 7)
# ∂springforceb∂posb(joint::Translational3{T}, body1::Origin, body2::Component, Δt::T; attjac::Bool = true) where T = attjac ? szeros(T, 6, 6) : szeros(T, 6, 7)
# ∂damperforceb∂posb(joint::Translational3{T}, body1::Origin, body2::Component, Δt::T; attjac::Bool = true) where T = attjac ? szeros(T, 6, 6) : szeros(T, 6, 7)

∂springforcea∂vela(joint::Translational3{T}, body1::Component, body2::Component, Δt::T) where T = szeros(T, 6, 6)
∂damperforcea∂vela(joint::Translational3{T}, body1::Component, body2::Component, Δt::T) where T = szeros(T, 6, 6)
∂springforcea∂velb(joint::Translational3{T}, body1::Component, body2::Component, Δt::T) where T = szeros(T, 6, 6)
∂damperforcea∂velb(joint::Translational3{T}, body1::Component, body2::Component, Δt::T) where T = szeros(T, 6, 6)
∂springforceb∂velb(joint::Translational3{T}, body1::Component, body2::Component, Δt::T) where T = szeros(T, 6, 6)
∂damperforceb∂velb(joint::Translational3{T}, body1::Component, body2::Component, Δt::T) where T = szeros(T, 6, 6)
∂springforceb∂vela(joint::Translational3{T}, body1::Component, body2::Component, Δt::T) where T = szeros(T, 6, 6)
∂damperforceb∂vela(joint::Translational3{T}, body1::Component, body2::Component, Δt::T) where T = szeros(T, 6, 6)
∂springforceb∂velb(joint::Translational3{T}, body1::Origin, body2::Component, Δt::T) where T = szeros(T, 6, 6)
∂damperforceb∂velb(joint::Translational3{T}, body1::Origin, body2::Component, Δt::T) where T = szeros(T, 6, 6)

function ∂springforcea∂posa(joint::Translational, body1::Component, body2::Component, Δt::T; attjac::Bool = true) where T
    xa, qa = posargs2(body1.state)
    xb, qb = posargs2(body2.state)

    X = FiniteDiff.finite_difference_jacobian(xa -> springforcea(joint, xa, qa, xb, qb), xa)
    Q = FiniteDiff.finite_difference_jacobian(qa -> springforcea(joint, xa, UnitQuaternion(qa..., false), xb, qb), [qa.w, qa.x, qa.y, qa.z])
    attjac && (Q *= LVᵀmat(qa))
    return Δt * [X Q]
end
function ∂damperforcea∂posa(joint::Translational, body1::Component, body2::Component, Δt::T; attjac::Bool = true) where T
    xa, qa = posargs2(body1.state)
    xb, qb = posargs2(body2.state)
    va = body1.state.vsol[2]
    vb = body2.state.vsol[2]
    ωa = body1.state.ϕsol[2]
    ωb = body2.state.ϕsol[2]

    X = FiniteDiff.finite_difference_jacobian(xa -> damperforcea(joint, xa, qa, va, ωa, xb, qb, vb, ωb), xa)
    Q = FiniteDiff.finite_difference_jacobian(qa -> damperforcea(joint, xa, UnitQuaternion(qa..., false), va, ωa, xb, qb, vb, ωb), [qa.w, qa.x, qa.y, qa.z])
    attjac && (Q *= LVᵀmat(qa))
    return Δt * [X Q]
end

function ∂springforcea∂posb(joint::Translational, body1::Component, body2::Component, Δt::T; attjac::Bool = true) where T
    xa, qa = posargs2(body1.state)
    xb, qb = posargs2(body2.state)

    X = FiniteDiff.finite_difference_jacobian(xb -> springforcea(joint, xa, qa, xb, qb), xb)
    Q = FiniteDiff.finite_difference_jacobian(qb -> springforcea(joint, xa, qa, xb, UnitQuaternion(qb..., false)), [qb.w, qb.x, qb.y, qb.z])
    attjac && (Q *= LVᵀmat(qb))
    return Δt * [X Q]
end

function ∂damperforcea∂posb(joint::Translational, body1::Component, body2::Component, Δt::T; attjac::Bool = true) where T
    xa, qa = posargs2(body1.state)
    xb, qb = posargs2(body2.state)
    va = body1.state.vsol[2]
    vb = body2.state.vsol[2]
    ωa = body1.state.ϕsol[2]
    ωb = body2.state.ϕsol[2]

    X = FiniteDiff.finite_difference_jacobian(xb -> damperforcea(joint, xa, qa, va, ωa, xb, qb, vb, ωb), xb)
    Q = FiniteDiff.finite_difference_jacobian(qb -> damperforcea(joint, xa, qa, va, ωa, xb, UnitQuaternion(qb..., false), vb, ωb), [qb.w, qb.x, qb.y, qb.z])
    attjac && (Q *= LVᵀmat(qb))
    return Δt * [X Q]
end

function ∂springforceb∂posb(joint::Translational, body1::Component, body2::Component, Δt::T; attjac::Bool = true) where T
    xa, qa = posargs2(body1.state)
    xb, qb = posargs2(body2.state)

    X = FiniteDiff.finite_difference_jacobian(xb -> springforceb(joint, xa, qa, xb, qb), xb)
    Q = FiniteDiff.finite_difference_jacobian(qb -> springforceb(joint, xa, qa, xb, UnitQuaternion(qb..., false)), [qb.w, qb.x, qb.y, qb.z])
    attjac && (Q *= LVᵀmat(qb))
    return Δt * [X Q]
end

function ∂damperforceb∂posb(joint::Translational, body1::Component, body2::Component, Δt::T; attjac::Bool = true) where T
    xa, qa = posargs2(body1.state)
    xb, qb = posargs2(body2.state)
    va = body1.state.vsol[2]
    vb = body2.state.vsol[2]
    ωa = body1.state.ϕsol[2]
    ωb = body2.state.ϕsol[2]

    X = FiniteDiff.finite_difference_jacobian(xb -> damperforceb(joint, xa, qa, va, ωa, xb, qb, vb, ωb), xb)
    Q = FiniteDiff.finite_difference_jacobian(qb -> damperforceb(joint, xa, qa, va, ωa, xb, UnitQuaternion(qb..., false), vb, ωb), [qb.w, qb.x, qb.y, qb.z])
    attjac && (Q *= LVᵀmat(qb))
    return Δt * [X Q]
end
function ∂springforceb∂posa(joint::Translational, body1::Component, body2::Component, Δt::T; attjac::Bool = true) where T
    xa, qa = posargs2(body1.state)
    xb, qb = posargs2(body2.state)

    X = FiniteDiff.finite_difference_jacobian(xa -> springforceb(joint, xa, qa, xb, qb), xa)
    Q = FiniteDiff.finite_difference_jacobian(qa -> springforceb(joint, xa, UnitQuaternion(qa..., false), xb, qb), [qa.w, qa.x, qa.y, qa.z])
    attjac && (Q *= LVᵀmat(qa))
    return Δt * [X Q]
end
function ∂damperforceb∂posa(joint::Translational, body1::Component, body2::Component, Δt::T; attjac::Bool = true) where T
    xa, qa = posargs2(body1.state)
    xb, qb = posargs2(body2.state)
    va = body1.state.vsol[2]
    vb = body2.state.vsol[2]
    ωa = body1.state.ϕsol[2]
    ωb = body2.state.ϕsol[2]

    X = FiniteDiff.finite_difference_jacobian(xa -> damperforceb(joint, xa, qa, va, ωa, xb, qb, vb, ωb), xa)
    Q = FiniteDiff.finite_difference_jacobian(qa -> damperforceb(joint, xa, UnitQuaternion(qa..., false), va, ωa, xb, qb, vb, ωb), [qa.w, qa.x, qa.y, qa.z])
    attjac && (Q *= LVᵀmat(qa))
    return Δt * [X Q]
end
# function ∂springforceb∂posb(joint::Translational, body1::Origin, body2::Component, Δt::T; attjac::Bool = true) where T
#     xb, qb = posargs2(body2.state)

#     X = FiniteDiff.finite_difference_jacobian(xb -> springforceb(joint, xb, qb), xb)
#     Q = FiniteDiff.finite_difference_jacobian(qb -> springforceb(joint, xb, UnitQuaternion(qb..., false)), [qb.w, qb.x, qb.y, qb.z])
#     attjac && (Q *= LVᵀmat(qb))
#     return Δt * [X Q]
# end
# function ∂damperforceb∂posb(joint::Translational, body1::Origin, body2::Component, Δt::T; attjac::Bool = true) where T
#     xb, qb = posargs2(body2.state)
#     vb = body2.state.vsol[2]
#     ωb = body2.state.ϕsol[2]

#     X = FiniteDiff.finite_difference_jacobian(xb -> damperforceb(joint, xb, qb, vb, ωb), xb)
#     Q = FiniteDiff.finite_difference_jacobian(qb -> damperforceb(joint, xb, UnitQuaternion(qb..., false), vb, ωb), [qb.w, qb.x, qb.y, qb.z])
#     attjac && (Q *= LVᵀmat(qb))
#     return Δt * [X Q]
# end

function ∂springforcea∂vela(joint::Translational, body1::Component, body2::Component, Δt::T) where T
    return Δt * szeros(T, 6, 6)
end

function ∂damperforcea∂vela(joint::Translational, body1::Component, body2::Component, Δt::T) where T
    xa, qa = posargs2(body1.state)
    xb, qb = posargs2(body2.state)
    va = body1.state.vsol[2]
    ωa = body1.state.ϕsol[2]
    vb = body2.state.vsol[2]
    ωb = body2.state.ϕsol[2]

    V = FiniteDiff.finite_difference_jacobian(va -> damperforcea(joint, xa, qa, va, ωa, xb, qb, vb, ωb), va)
    Ω = FiniteDiff.finite_difference_jacobian(ωa -> damperforcea(joint, xa, qa, va, ωa, xb, qb, vb, ωb), ωa)
    return Δt * [V Ω]
end

function ∂springforcea∂velb(joint::Translational, body1::Component, body2::Component, Δt::T) where T
    return Δt * szeros(T, 6, 6)
end

function ∂damperforcea∂velb(joint::Translational, body1::Component, body2::Component, Δt::T) where T
    xa, qa = posargs2(body1.state)
    xb, qb = posargs2(body2.state)
    va = body1.state.vsol[2]
    ωa = body1.state.ϕsol[2]
    vb = body2.state.vsol[2]
    ωb = body2.state.ϕsol[2]

    V = FiniteDiff.finite_difference_jacobian(vb -> damperforcea(joint, xa, qa, va, ωa, xb, qb, vb, ωb), vb)
    Ω = FiniteDiff.finite_difference_jacobian(ωb -> damperforcea(joint, xa, qa, va, ωa, xb, qb, vb, ωb), ωb)
    return Δt * [V Ω]
end

function ∂springforceb∂velb(joint::Translational, body1::Component, body2::Component, Δt::T) where T
    return Δt * szeros(T, 6, 6)
end

function ∂damperforceb∂velb(joint::Translational, body1::Component, body2::Component, Δt::T) where T
    xa, qa = posargs2(body1.state)
    xb, qb = posargs2(body2.state)
    va = body1.state.vsol[2]
    ωa = body1.state.ϕsol[2]
    vb = body2.state.vsol[2]
    ωb = body2.state.ϕsol[2]

    V = FiniteDiff.finite_difference_jacobian(vb -> damperforceb(joint, xa, qa, va, ωa, xb, qb, vb, ωb), vb)
    Ω = FiniteDiff.finite_difference_jacobian(ωb -> damperforceb(joint, xa, qa, va, ωa, xb, qb, vb, ωb), ωb)
    return Δt * [V Ω]
end

function ∂springforceb∂vela(joint::Translational, body1::Component, body2::Component, Δt::T) where T
    return Δt * szeros(T, 6, 6)
end

function ∂damperforceb∂vela(joint::Translational, body1::Component, body2::Component, Δt::T) where T
    xa, qa = posargs2(body1.state)
    xb, qb = posargs2(body2.state)
    va = body1.state.vsol[2]
    ωa = body1.state.ϕsol[2]
    vb = body2.state.vsol[2]
    ωb = body2.state.ϕsol[2]

    V = FiniteDiff.finite_difference_jacobian(va -> damperforceb(joint, xa, qa, va, ωa, xb, qb, vb, ωb), va)
    Ω = FiniteDiff.finite_difference_jacobian(ωa -> damperforceb(joint, xa, qa, va, ωa, xb, qb, vb, ωb), ωa)
    return Δt * [V Ω]
end

# function ∂springforceb∂velb(joint::Translational, body1::Origin, body2::Component, Δt::T) where T
#     return Δt * szeros(T, 6, 6)
# end
# function ∂damperforceb∂velb(joint::Translational, body1::Origin, body2::Component, Δt::T) where T
#     xb, qb = posargs2(body2.state)
#     vb = body2.state.vsol[2]
#     ωb = body2.state.ϕsol[2]

#     V = FiniteDiff.finite_difference_jacobian(vb -> damperforceb(joint, xb, qb, vb, ωb), vb)
#     Ω = FiniteDiff.finite_difference_jacobian(ωb -> damperforceb(joint, xb, qb, vb, ωb), ωb)
#     return Δt * [V Ω]
# end