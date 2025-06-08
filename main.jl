# imports
using JuMP, GLPK, CSV, DataFrames

# data preprocessing
sectors_df = DataFrame(CSV.File("mariah_airport_sectors.csv"))

airports_df = dropmissing(sectors_df)

airports_list = string.(airports_df.airport)

airports = Dict(string.(sectors_df.airport[i]) => [sectors_df[i, col] for col in 6:ncol(sectors_df)] for i in 1:nrow(sectors_df))

sectors = Dict(string.(sectors_df.sector[i]) => sectors_df.sector_capacity[i] for i in 1:nrow(sectors_df))

sectors_list = string.(sectors_df.sector)

timetable_df = DataFrame(CSV.File("mariah_timetable.csv"))

sector_lookup = Dict(sectors_df.sector[i] => i for i in 1:nrow(sectors_df))

airport_lookup = Dict(sectors_df.airport[i] => i for i in 1:nrow(sectors_df))

l = DataFrame(CSV.File("min_times_anu.csv", header = false))

start_df = DataFrame(CSV.File("flight_min_times_anu.csv", header = false))

buffer_time = 1


P = DataFrame(CSV.File("flight_paths_anu.csv", header = false))

# Preparing an optimization model
m = Model(GLPK.Optimizer)

F = nrow(timetable_df)
K = nrow(airports_df)
J = nrow(sectors_df)
N = [sum([P[j,i] != "0" for j in 1:nrow(P)]) for i in 1:ncol(P)]


T = 100

c = [10location for flight in 1:F, location in 1:2]


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

function Tjf(f, j)
    start_time = start_df[j, f]
    end_time = start_time + buffer_time
    return start_time:end_time
end

function W(f, t, j)
    f = convert(Int, f)
    t = convert(Int, t)
    j = convert(Int, j)

    return w[P[j, f]][f, t]
end
# Declaring variables

w = Dict(sector => [@variable(m, binary = true) for f in 1:F, t in 1:T] for sector in hcat(sectors_list, airports_list))

# Setting the objective
@objective(m, Min, sum(((c[f,1]-c[f,2]) * sum(t*(W(f, t, 1) - W(f, t-1, 1)) for t in Tjf(f, 1))) + (c[f, 2] * sum(t*(W(f, t, N[f]) - W(f, t-1, N[f])) for t in Tjf(f, N[f]))) for f in 1:F))


println("Objective good")
# Adding constraints

# airport and sector capacity constraints
for k in 1:K, t in 2:T
    @constraint(m, sum(W(f, t, 1) - W(f, t-1, 1) for f in 1:F) <= D(k, t))
    @constraint(m, sum(W(f, t, N[f]) - W(f, t-1, N[f]) for f in 1:F) <= A(k, t))
end
for j in 1:J, t in 2:T
    @constraint(m, sum(W(f, t, j) - W(f, t, j+1) for f in 1:F if j < N[f]) <= S(j, t))
end

# connectivity constraints
for f in 1:F
    for j in 1:N[f]-1
        # didn't include connecting flights
        for t in Tjf(f, i)
            @constraint(m, W(f, t + l[i, f], j + 1) - W(f, t, j) <= 0)
        end
    end

    for j in 1:N[f]
        for t in Tjf(f, j)
            @constraint(m, W(f, t, j) - W(f, t-1, j) >= 0)
        end
    end
end

# Solving the optimization problem
JuMP.optimize!(m)

# Print the information about the optimum.
println("Total Cost: ", objective_value(m))
println(sum(value.(w["A"])))