@testset "Behavior: Quadruped simulation" begin
    mech = get_mechanism(:quadruped, 
        timestep=0.05, 
        gravity=-9.81, 
        friction_coefficient=0.8, 
        damper=1000.0, 
        spring=30.0)

    initialize!(mech, :quadruped)

    try
        storage = simulate!(mech, 5.0, 
            record=true, 
            verbose=false)
        @test true
    catch
        @test false
    end
end

@testset "Behavior: Box toss" begin
    for timestep in [0.10, 0.05, 0.01, 0.005]
        mech = get_mechanism(:box, 
            timestep=timestep, 
            gravity=-9.81, 
            friction_coefficient = 0.1)

        initialize!(mech, :box, 
            x=[0.0, 0.0, 0.5], 
            v=[1.0, 1.5, 1.0], 
            ω=[5.0, 4.0, 2.0] .* timestep)
        storage = simulate!(mech, 5.0, 
            record=true,
            opts=SolverOptions(btol=1e-6, rtol=1e-6, 
            verbose=false))

        @test norm(storage.v[1][end], Inf) < 1e-12
        @test norm(storage.x[1][end][3] - 0.25, Inf) < 1e-3
    end
end

@testset "Behavior: Four-bar linkage" begin
    for timestep in [0.10, 0.05, 0.01, 0.005]
        # Mechanism
        timestep = 0.10
        mech = Dojo.get_fourbar(
            model="fourbar", 
            timestep=timestep)
        Dojo.initialize!(mech, :fourbar, 
            angle=0.1, 
            angular_velocity=[3.0, -3.0]) 
        loopjoints = mech.joints[end:end]
        Dojo.root_to_leaves_ordering(mech) == [2, 7, 3, 6, 1, 8, 4, 9]

        # Simulation
        function ctrl!(m,k)
            Dojo.set_input!(m, 20 * m.timestep * SVector(rand(), -rand(), 0.0, 0.0, 0.0))
            return nothing
        end
        storage = Dojo.simulate!(mech, 5.0, ctrl!, verbose=false, record=true)

        min_coords = Dojo.get_minimal_coordinates(mech)
        @test norm(min_coords[5] - +min_coords[4], Inf) < 1.0e-5
        @test norm(min_coords[5] - -min_coords[3], Inf) < 1.0e-5
        @test norm(min_coords[5] - (min_coords[2] - min_coords[1]), Inf) < 1.0e-5
    end
end