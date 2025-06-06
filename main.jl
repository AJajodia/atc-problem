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

# Declaring variables
@variable(m, w[1:F, T, 1:J])

# Setting the objective
@objective(m, Min, sum(((c[f,1]-c[f,2]) * sum(t*(w[f, t, P_a(f, 1)] - w[f, t-1, P_a(f, N[f])]) for t in T)) + c[f, 2] for f in 1:F))

# Adding constraints

# airport and sector capacity constraints
for k in 1:K, t in 1:T
    @constraint(m, sum((w[f, t, 1] - w[f, t-1, 1]) for f in 1:F if P[k][1] == k) <= D[t][k])
    @constraint(m, sum((w[f, t, 1] - w[f, t-1, 1]) for f in 1:F if P[k][1] == k) <= A[t][k])
    @constraint(m, )
end

# connectivity constraints

# Printing the prepared optimization model
print(m)

# Solving the optimization problem
JuMP.optimize!(m)

# Print the information about the optimum.
println("Objective value: ", objective_value(m))
println("Optimal solutions:")
println("y1 = ", value(y1))
println("y2 = ", value(y2))