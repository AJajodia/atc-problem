using JuMP
using GLPK
using CSV
using DataFrames

# Load preprocessed data
paths_df = CSV.read("flight_paths_anu.csv", DataFrame, header=false)
durations_df = CSV.read("min_times_anu.csv", DataFrame, header=false)
mintimes_df = CSV.read("flight_min_times_anu.csv", DataFrame, header=false)

num_flights = size(paths_df, 2)
max_segments = size(paths_df, 1)

# Parameters
ground_cost = 5
air_cost = 10

model = Model(GLPK.Optimizer)

# Variables: T[f, s] is the time flight f enters segment s
@variable(model, T[1:num_flights, 1:max_segments] >= 0)

# Constraint 1: Timing consistency
for f in 1:num_flights
    for s in 1:max_segments-1
        if paths_df[s+1, f] != 0  # Ensure it's a valid segment
            @constraint(model, 
                T[f, s+1] ≥ T[f, s] + durations_df[s, f])
        end
    end
end

# Constraint 2: Minimum start time
for f in 1:num_flights
    @constraint(model, 
        T[f, 1] ≥ mintimes_df[1, f])
end

# Objective: Minimize total delay cost
@expression(model, total_cost,
    sum(
        (T[f, s] - mintimes_df[s, f]) *
        (s == 1 ? ground_cost : air_cost)
        for f in 1:num_flights, s in 1:max_segments if paths_df[s, f] != 0
    )
)

@objective(model, Min, total_cost)

optimize!(model)

# Print solution
if termination_status(model) == MOI.OPTIMAL
    println("Optimal schedule found.")
    results = DataFrame()
    for f in 1:num_flights
        results[!, Symbol("Flight_$f")] = [value(T[f, s]) for s in 1:max_segments]
    end
    CSV.write("optimal_schedule.csv", results)
else
    println("Optimization did not find an optimal solution.")
end
