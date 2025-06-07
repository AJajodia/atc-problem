# imports
using JuMP, GLPK, CSV, DataFrames

# data preprocessing
sectors_df = DataFrame(CSV.File("mariah_airports.csv"))

airports_df = dropmissing(sectors_df)

airports_list = airports_df.airport

airports = Dict(sectors_df.airport[i] => [sectors_df[i, col] for col in 6:ncol(sectors_df)] for i in 1:nrow(sectors_df))

sectors = Dict(sectors_df.sector[i] => sectors_df.sector_capacity[i] for i in 1:nrow(sectors_df))

sectors_list = sectors_df.sector

timetable_df = DataFrame(CSV.File("mariah_timetable.csv"))

sector_lookup = Dict(sectors_df.sector[i] => i for i in 1:nrow(sectors_df))

airport_lookup = Dict(sectors_df.airport[i] => i for i in 1:nrow(sectors_df))


P = DataFrame(CSV.File("flight_paths.csv", header = false))


# Preparing an optimization model
m = Model(GLPK.Optimizer)

F = nrow(timetable_df)
K = nrow(airports_df)
J = nrow(sectors_df)
N = [sum([flights[j,i] != "0" for j in 1:nrow(P)]) for i in 1:ncol(P)]


T = [minimum(timetable_df.depart_time): maximum(timetable_df.arrival_time)]

c = [10location for flight in 1:F, location in 1:2]

println(c)

function D(k, t)
    airport = airports_list[k]
    airports[airport][8]
end

function A(k, t)
    airport = airports_list[k]
    return airports[airport][9]
end

function S(j, t)
    sector = sectors_list[j]
    return sectors[sector]
end


function P_s(f, i)
    sector = P[i,f]
    return sector_lookup[sector]
end

function P_a(f, i)
    airport = P[i, f]
    return airport_lookup[airport]
end

function Tjf(f, j)
    # start_time = start_df[f, j]
    # end_time = end_df[f, j]
    start_time = 1
    end_time = 24
    return start_time:end_time
end

# Declaring variables
@variable(m, w[1:F, T, 1:J], Bin)

# Setting the objective
@objective(m, Min, sum(((c[f,1]-c[f,2]) * sum(t*(w[f, t, P_a(f, 1)] - w[f, t-1, P_a(f, 1)]) for t in T)) + (c[f, 2] * sum(t*(w[f, t, P_a(f, N[f])] - w[f, t-1, P_a(f, N[f])]) for t in T)) for f in 1:F))

# Adding constraints

# airport and sector capacity constraints
for k in 1:K, t in T
    @constraint(m, sum((w[f, t, P_a(f, 1)] - w[f, t-1, P_a(f, 1)]) for f in 1:F) <= D(k, t))
    @constraint(m, sum((w[f, t, P_a(f, N[f])] - w[f, t-1, P_a(f, N[f])]) for f in 1:F) <= A(k, t))
end
for j in 1:J, t in T
    @constraint(m, sum(sum(w[f, t, P_a(f, i)] - w[f, t, P_a(f, i+1)] for i in 1:N[f]-1) for f in 1:F) <= S(k, t))
end

# connectivity constraints
for f in 1:F
    for i in 1:N[f]-1
        # didn't include connecting flights
        for t in Tjf(f, j)
            @constraint(w[f, t + l[f, P_a(f, i)], P_a(f, i+1)] - w[f, t, P_a(f, i)] <= 0)
        end
    end

    for j in 1:N[f]
        for t in Tjf(f, j)
            @constraint(w[f, t, P_s(f, j)] - w[f, t-1, P_s(f, j)])
        end
    end
end

# Printing the prepared optimization model
print(m)

# Solving the optimization problem
JuMP.optimize!(m)

# Print the information about the optimum.
println("Total Cost: ", objective_value(m))