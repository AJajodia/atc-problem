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
sector_dict = Dict(row.sector => (row.xmin, row.xmax, row.ymin, row.ymax) 
for row in eachrow(airport_sectors))


# create straight line that flight follows
function line_flight_path(origin, destination, step_size)
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
function in_sector(x, y, xmin, xmax, ymin, ymax)
    return xmin ≤ x ≤ xmax && ymin ≤ y ≤ ymax
end

# find what sectors a flight crosses (straight line)
function sector_flight_path(start_end, bounds)
    crossed_sectors = Array{Float64,1}()
    for (i, bounds) in enumerate(bounds_list)
        for (x, y) in path
            if in_sector(x, y, bounds)
                push!(sectors, i)
                break  # Only need to check once per sector
            end
        end
    end
    return sort(collect(sectors))
end
