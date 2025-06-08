using Random
using DataFrames
using CSV

airport_sectors = CSV.read("mariah_airport_sectors.csv", DataFrame) 
timetable = CSV.read("mariah_timetable.csv", DataFrame, 
types=Dict(:depart_airport => String, :arrive_airport => String))

# --- Step 4: Create dictionaries for sector boundaries and airport coords ---
airport_dict = Dict(row.airport => (row.airport_lat, row.airport_long) for row in eachrow(airport_sectors) if !ismissing(row.airport))
sector_dict = Dict(row.sector => (xmin=row.xmin, xmax=row.xmax, ymin=row.ymin, ymax=row.ymax) for row in eachrow(airport_sectors))

# --- Step 5: Flight path function, line interpolation ---
function line_path(origin, destination, step_size=0.01)
    start_coord = airport_dict[origin]
    end_coord = airport_dict[destination]

    x1, y1 = start_coord[2], start_coord[1]
    x2, y2 = end_coord[2], end_coord[1]

    total_steps = max(ceil(Int, abs(x2 - x1) / step_size), ceil(Int, abs(y2 - y1) / step_size))
    flight_line = []

    for i in 0:total_steps
        t = i / total_steps
        x = x1 + t * (x2 - x1)
        y = y1 + t * (y2 - y1)
        push!(flight_line, (x, y))
    end
    return flight_line
end

# --- Step 6: Find sector for a point ---
function find_sector(x, y)
    for (sector, bounds) in sector_dict
        if x ≥ bounds.xmin && x ≤ bounds.xmax && y ≥ bounds.ymin && y ≤ bounds.ymax
            return sector
        end
    end
    return nothing
end

# --- Step 7: Compute sector durations for flight line ---
function sector_durations(flight_line, airspeed)
    sector_entries = Dict{Any, Tuple{Float64, Float64}}()
    sector_exits = Dict{Any, Tuple{Float64, Float64}}()

    for (x, y) in flight_line
        sector = find_sector(x, y)
        if sector === nothing
            continue
        end
        if !haskey(sector_entries, sector)
            sector_entries[sector] = (x, y)
        end
        sector_exits[sector] = (x, y)
    end

    sector_times = Dict{Any, Float64}()
    for sector in keys(sector_entries)
        entry = sector_entries[sector]
        exit = sector_exits[sector]
        dist = sqrt((100 * (exit[1] - entry[1]))^2 + (100 * (exit[2] - entry[2]))^2)
        time = dist / airspeed
        sector_times[sector] = round(time + 1)  # Rounded integer times
    end

    return sector_times
end

# --- Step 8: Compute full flight path for each flight ---
function flight_path(row_number, step_size=0.01)
    row = timetable[row_number, :]
    flight_lines = []
    flight_times = []
    flight_min_times = []

    depart_airport = row.depart_airport
    arrive_airport = row.arrive_airport
    depart_time = row.depart_time
    airspeed = row.airspeed

    flight_line = line_path(depart_airport, arrive_airport, step_size)
    sector_times = sector_durations(flight_line, airspeed)

    push!(flight_lines, depart_airport)
    push!(flight_times, 0)
    push!(flight_min_times, depart_time)

    seen_sectors = Set{Any}()

    for (x, y) in flight_line
        sector = find_sector(x, y)
        if sector === nothing || sector in seen_sectors
            continue
        end
        push!(flight_lines, sector)
        push!(flight_min_times, flight_min_times[end] + flight_times[end])
        push!(flight_times, sector_times[sector])
        push!(seen_sectors, sector)
    end

    push!(flight_lines, arrive_airport)
    push!(flight_min_times, flight_min_times[end] + flight_times[end])
    push!(flight_times, 0)

    return flight_lines, flight_times, flight_min_times
end

# --- Step 9: Process all flights and pad for matrix ---
all_paths = []
all_times = []
all_min_times = []
global max_length = 2

for i in 1:nrow(timetable)
    path, time, min_time = flight_path(i)
    global max_length = max(max_length, length(path))
    push!(all_paths, path)
    push!(all_times, time)
    push!(all_min_times, min_time)
end

# Pad lists to max_length
function pad_to_length(arr, len, pad_value)
    while length(arr) < len
        push!(arr, pad_value)
    end
    return arr
end

for i in 1:length(all_paths)
    all_paths[i] = pad_to_length(all_paths[i], max_length, missing)
    all_times[i] = pad_to_length(all_times[i], max_length, 0)
    all_min_times[i] = pad_to_length(all_min_times[i], max_length, 0)
end

# --- Step 10: Convert padded data into DataFrames for CSV ---

paths_df = DataFrame()
for i in 1:max_length
    col = [row[i] for row in all_paths]
    paths_df[!, "path_$i"] = col
end
CSV.write("flight_paths2.csv", paths_df)

times_df = DataFrame()
for i in 1:max_length
    col = [row[i] for row in all_times]
    times_df[!, "time_$i"] = col
end
CSV.write("sector_times.csv", times_df)

mintimes_df = DataFrame()
for i in 1:max_length
    col = [row[i] for row in all_min_times]
    mintimes_df[!, "mintime_$i"] = col
end
CSV.write("sector_mintimes.csv", mintimes_df)

# --- Step 11: Generate time-varying capacities ---
T = 96  # time horizon (e.g. 15 min increments over 24h)

# Sector capacities (sector x time)
sector_capacities = DataFrame(sector = Int[], time = Int[], capacity = Int[])
for sector in 1:9
    for t in 1:T
        push!(sector_capacities, (sector, t, rand(2:4)))
    end
end
CSV.write("sector_capacities.csv", sector_capacities)

# Airport departure and arrival capacities
airport_list = unique(skipmissing(airport_sectors.airport))
depart_caps = DataFrame(airport = String[], time = Int[], capacity = Int[])
arrival_caps = DataFrame(airport = String[], time = Int[], capacity = Int[])

for airport in airport_list
    for t in 1:T
        push!(depart_caps, (airport, t, rand(2:5)))
        push!(arrival_caps, (airport, t, rand(2:5)))
    end
end

CSV.write("departure_capacities.csv", depart_caps)
CSV.write("arrival_capacities.csv", arrival_caps)

# --- Step 12: Compose dictionaries for delay costs ---
delay_costs = DataFrame(cost_type=String[], cost_value=Int[])
push!(delay_costs, ("ground_delay", ground_cost))
push!(delay_costs, ("air_delay", air_cost))
CSV.write("delay_costs.csv", delay_costs)