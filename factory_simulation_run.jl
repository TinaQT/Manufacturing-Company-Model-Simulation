include("factory_simulation.jl")

using CSV, DataFrames

for seed ∈ 1:100 
    # read the csv file and store it as DataFrame   
    parameter = CSV.File("parameters.csv"; header=2)  # the first line is comment with "# paramerters", so skip it
    df = DataFrame(parameter)

    # Create a dictionary to store the values
    values_dict = Dict{String, Float64}()

    # assign values
    for col in names(df)
        values_dict[col] = df[1, col]
    end

    # output the values
    mean_interarrival = values_dict["mean_interarrival"]
    mean_construction_time = values_dict["mean_construction_time"]
    mean_interbreakdown_time = values_dict["mean_interbreakdown_time"]
    mean_repair_time = values_dict["mean_repair_time"]

    T = 1000.0
    P = Parameters(seed, T, mean_interarrival, mean_construction_time, mean_interbreakdown_time, mean_repair_time)

    # file directory and names
    dir = pwd()*"/data/"*"/seed"*string(P.seed)*"/T"*string(P.T)*"/mean_interarrival"*string(P.mean_interarrival)*"/mean_construction_time"*string(P.mean_construction_time)*"/mean_interbreakdown_time"*string(P.mean_interbreakdown_time)*"/mean_repair_time"*string(P.mean_repair_time)
    mkpath(dir)                          # this creates the directory 
    file_entities = dir*"/entities.csv"  # the name of the data file (informative) 
    file_state = dir*"/state.csv"        # the name of the data file (informative) 
    fid_entities = open(file_entities, "w") # open the file for writing
    fid_state = open(file_state, "w")       # open the file for writing

    write_metadata( fid_entities )
    write_metadata( fid_state )
    write_parameters( fid_entities, P )
    write_parameters( fid_state, P )

    # headers
    write_entity_header( fid_entities,  Order(0, 0.0) )
    println(fid_state,"time,event_id,event_type,length_event_list,length_queue,in_service,machine_status")

    # run the actual simulation
    (system,R) = initialise( P ) 
    run!( system, P, R, fid_state, fid_entities)

    # close the files
    close( fid_entities )
    close( fid_state )
end

# this part is for part 2 when manually input all the relevant data
# seed = 1
# mean_interarrival = 60.0
# mean_construction_time = 25.0
# mean_interbreakdown_time = 2880.0
# mean_repair_time = 180.0

# end of code