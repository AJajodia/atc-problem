using Random
using DataFrames
using CSV

#loading R simulated data
airport_sectors = CSV.read("optimization_project/mariah_airport_sectors.csv", DataFrame) 
timetable = CSV.read("optimization_project/mariah_timetable.csv", DataFrame)

#creating a dictionary for the coordinates of each airport
airport_dict = Dict(row.airport => (row.airport_lat, row.airport_long) 
for row in eachrow(airport_sectors))

#creating a dictionary for the boundaries of each sector
sector_dict = Dict(row.sector => (xmin = row.xmin, xmax = row.xmax, 
ymin = row.ymin, ymax =row.ymax) 
for row in eachrow(airport_sectors))


# create straight line that flight follows
function line_path(origin, destination, step_size)
    start_coord = airport_dict[origin]
    end_coord = airport_dict[destination]

    x1 = start_coord[2]
    x2 = end_coord[2]
    y1 = start_coord[1]
    y2 = end_coord[1]

    total_steps = max(
        ceil(Int, abs(x2 - x1) / step_size),
        ceil(Int, abs(y2 - y1) / step_size)
    )

    flight_line = []

    for i in 0:total_steps
        t = i / total_steps
        x = x1 + t * (x2 - x1)
        y = y1 + t * (y2 - y1)
        push!(flight_line, (x, y))
    end

    return flight_line

end

# checker to see if a given point is in a sector (can check along the flight line)
function find_sector(x, y)
    for (sector, bounds) in sector_dict
        if x ≥ bounds.xmin && x ≤ bounds.xmax && y ≥ bounds.ymin && y ≤ bounds.ymax
            return sector
        end
    end
end

# find what sectors a flight line crosses
function flight_path(row_number)
    depart_airport = timetable[row_number, 2]
    depart_sector = timetable[row_number, 3]
    arrive_airport = timetable[row_number, 4]
    #arrive_sector = timetable[row_number, 5]

    flight_line = line_path(depart_airport, arrive_airport, 0.1)

    flight_path = [depart_airport, depart_sector]

    for (x,y) in flight_line
        s = find_sector(x,y)
        if s ∉ flight_path
            push!(flight_path, s)
        end
    end 
    push!(flight_path, arrive_airport)   
    
    return flight_path
end

# find longest path
global max_length = 2
all_paths = []
for i in 1:nrow(timetable)
    path = flight_path(i)
    push!(all_paths, path)
    if length(path) > max_length
        global max_length = length(path)
    end
end

# pad remaining paths with Os
padded = [hcat(path, fill(0, max_length - length(path))) for path in all_paths]

column_names = ["flight_$(i)" for i in 1:20]
padded_df = DataFrame(padded, Symbol.(column_names))
CSV.write("flight_paths.csv", padded_df; writeheader = false)