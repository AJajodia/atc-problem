using JuMP, GLPK, CSV, DataFrames

# --- Data preprocessing ---

sectors_df = DataFrame(CSV.File("mariah_airport_sectors.csv"))
airports_df = filter(row -> all(x -> x != "NA", row), sectors_df)

# Lists of airports and sectors as strings
airports_list = string.(airports_df.airport)
sectors_list = string.(sectors_df.sector)

# Dictionaries for airports info () and sectors capacity data keyed by string
airports = Dict(string.(sectors_df.airport[i]) => [sectors_df[i, col] for col in 6:ncol(sectors_df)] for i in 1:nrow(sectors_df))
sector_capacity = Dict(string.(sectors_df.sector[i]) => sectors_df.sector_capacity[i] for i in 1:nrow(sectors_df))

# Timetable and lookup dictionaries
timetable_df = DataFrame(CSV.File("mariah_timetable.csv"))
sector_lookup = Dict(sectors_list[i] => i for i in 1:nrow(sectors_df))
airport_lookup = Dict(sectors_df.airport[i] => i for i in 1:nrow(sectors_df))

# Other data
l = DataFrame(CSV.File("min_times_anu.csv", header = false))
start_df = DataFrame(CSV.File("flight_min_times_anu.csv", header = false))
buffer_time = 4

# Flight paths: rows = steps along path, cols = flights
P = DataFrame(CSV.File("flight_paths_anu.csv", header = false))

# --- Model setup ---

m = Model(GLPK.Optimizer)

F = nrow(timetable_df)      # Number of flights
K = nrow(airports_df)       # Number of airports
J = nrow(sectors_df)        # Number of sectors (all sectors in system)

# N[f] = number of steps (sectors/airports) along flight f's path
N = [sum([P[step, f] != "0" for step in 1:nrow(P)]) for f in 1:ncol(P)]

T = 96  # number of time periods (96 fifteen minutes in 1 day)

# Cost matrix: rows = flights, columns = [ground cost, air cost]
c = zeros(F, 2)
for f in 1:F
    c[f, 1] = 10    # ground holding cost
    c[f, 2] = 100   # air holding cost
end

function Tjf(f, j)
    start_time = start_df[j, f]
    end_time = start_time + buffer_time
    return start_time:end_time
end

print(Tjf(2))