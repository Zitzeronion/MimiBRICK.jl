# #-------------------------------------------------------------------------------------------------------
# #-------------------------------------------------------------------------------------------------------
# # This file carries out all of the runs to replicate the results from "BRICK-SCC Paper".
# #-------------------------------------------------------------------------------------------------------
# #-------------------------------------------------------------------------------------------------------

# Activate the project for the paper and make sure all packages we need are installed.
using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
Pkg.instantiate()


# Load required Julia packages.
using CSVFiles
using DataFrames
using Distributions
using KernelDensity
using LinearAlgebra
using Mimi
using NetCDF
using RobustAdaptiveMetropolisSampler


# A folder with this name will be created to store all of the replication results.
results_folder_name = "my_results"

# Create output folder path for convenience and make path.
output = joinpath(@__DIR__, "..", "results", results_folder_name)
mkpath(output)

# Load calibration helper functions file.
include(joinpath("..", "calibration", "calibration_helper_functions.jl"))

# Set final year for model calibration.
calibration_end_year = 2017

# The length of the final chain (i.e. number of samples from joint posterior pdf after discarding burn-in period values).
final_chain_length = 100_000

# Length of burn-in period (i.e. number of initial MCMC samples to discard).
burn_in_length = 1_000


#-------------------------------------------------------------#
#-------------------------------------------------------------#
#------------ SNEASY + BRICK Baseline Calibration ------------#
#-------------------------------------------------------------#
#-------------------------------------------------------------#

# NOTE** This version uses the kernel density estimated marginal priors for the Antarctic ice sheet based on a calibration to paleo data.

# Load run historic model file.
include(joinpath("..", "calibration", "run_historic_models", "run_sneasy_brick_historic_climate.jl"))

# Load log-posterior file for SNEASY+BRICK model.
include(joinpath("..", "calibration", "create_log_posterior_sneasy_brick.jl"))

# Load inital parameter values for SNEASY+BRICK model.
initial_parameters_sneasybrick = DataFrame(load(joinpath(@__DIR__, "..", "data", "calibration_data", "calibration_initial_values_sneasy_brick.csv"), skiplines_begin=6))

# Load initial proposal covariance matrix (from previous calibrations) and format so it works with RAM sampler (need to account for rounding errors or Cholesky factorization fails).
initial_covariance_matrix_sneasybrick = Array(Hermitian(Matrix(DataFrame(load(joinpath(@__DIR__, "..", "data", "calibration_data", "initial_proposal_covariance_matrix_sneasybrick.csv"))))))

# Create `SNEASY+BRICK` function used in log-posterior calculations.
run_sneasybrick! = construct_run_sneasybrick(calibration_end_year)

# Create log-posterior function.
log_posterior_sneasy_brick = construct_sneasybrick_log_posterior(run_sneasybrick!, model_start_year=1850, calibration_end_year=calibration_end_year, joint_antarctic_prior=false)

println("Begin baseline calibration of SNEASY+BRICK model.\n")

# Carry out Bayesian calibration using robust adaptive metropolis MCMC algorithm.
chain_sneasybrick, accept_rate_sneasybrick, cov_matrix_sneasybrick = RAM_sample(log_posterior_sneasy_brick, initial_parameters_sneasybrick.starting_point, initial_covariance_matrix_sneasybrick, Int(final_chain_length + burn_in_length), opt_α=0.234)

# Discard burn-in values.
burned_chain_sneasybrick = chain_sneasybrick[Int(burn_in_length+1):end, :]

# Calculate mean posterior parameter values.
mean_sneasybrick = vec(mean(burned_chain_sneasybrick, dims=1))

# Calculate posterior correlations between parameters and set column names.
correlations_sneasybrick = DataFrame(cor(burned_chain_sneasybrick))
names!(correlations_sneasybrick, [Symbol(initial_parameters_sneasybrick.parameter[i]) for i in 1:length(mean_sneasybrick)])

# Create equally-spaced indices to thin chains down to 10,000 and 100,000 samples.
thin_indices_100k = trunc.(Int64, collect(range(1, stop=final_chain_length, length=100_000)))
thin_indices_10k  = trunc.(Int64, collect(range(1, stop=final_chain_length, length=10_000)))

# Create thinned chains (after burn-in period) with 10,000 and 100,000 samples and assign parameter names to each column.
thin100k_chain_sneasybrick = DataFrame(burned_chain_sneasybrick[thin_indices_100k, :])
thin10k_chain_sneasybrick  = DataFrame(burned_chain_sneasybrick[thin_indices_10k, :])

names!(thin100k_chain_sneasybrick, [Symbol(initial_parameters_sneasybrick.parameter[i]) for i in 1:length(mean_sneasybrick)])
names!(thin10k_chain_sneasybrick,  [Symbol(initial_parameters_sneasybrick.parameter[i]) for i in 1:length(mean_sneasybrick)])

#--------------------------------------------------#
#------------ Save Calibration Results ------------#
#--------------------------------------------------#

# Save calibrated parameter samples
println("Saving calibrated parameters for SNEASY+BRICK.\n")

# SNEASY-BRICK model calibration.
save(joinpath(@__DIR__, output, "mcmc_acceptance_rate.csv"), DataFrame(sneasybrick_acceptance=accept_rate_sneasybrick))
save(joinpath(@__DIR__, output, "proposal_covariance_matrix.csv"), DataFrame(cov_matrix_sneasybrick))
save(joinpath(@__DIR__, output, "mean_parameters.csv"), DataFrame(parameter = initial_parameters_sneasybrick.parameter[1:length(mean_sneasybrick)], sneasybrick_mean=mean_sneasybrick))
save(joinpath(@__DIR__, output, "parameters_10k.csv"), thin10k_chain_sneasybrick)
save(joinpath(@__DIR__, output, "parameters_100k.csv"), thin100k_chain_sneasybrick)
save(joinpath(@__DIR__, output, "posterior_correlations.csv"), correlations_sneasybrick)