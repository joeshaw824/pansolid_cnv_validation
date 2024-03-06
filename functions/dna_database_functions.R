# DNA Database Functions

# DNA database connection -----------------------------------------------------------

source(here::here("functions/dna_database_connection.R"))

# Database functions ----------------------------------------------------------------

get_columns <- function(table_input) {
  
  output <- odbc::odbcConnectionColumns(
    conn = dbi_con, 
    catalog_name = "MolecularDB",
    schema_name = "dbo",
    name = table_input)
  
  return(output)
  
}

get_extraction_method <- function(sample_vector) {
  
  extraction_tbl_samples <- extraction_tbl |> 
    filter(lab_no %in% sample_vector) |> 
    collect()
  
  batches <- unique(extraction_tbl_samples$extraction_batch_fk)
  
  extraction_batch_info <- extraction_batch_tbl |> 
    filter(extraction_batch_id %in% batches) |> 
    collect() |> 
    # Remove DNA dilutions
    filter(extraction_method_fk != 11) |>
    left_join(extraction_method_key, join_by(extraction_method_fk == extraction_method_id))
  
  output <- extraction_tbl_samples |> 
    left_join(extraction_batch_info, join_by(extraction_batch_fk == extraction_batch_id)) |> 
    filter(!is.na(method_name)) |> 
    janitor::clean_names() |> 
    rename(labno = lab_no)
  
  return(output)
  
}

get_sample_tissue <- function(sample_vector) {
  
  output <- sample_tbl |> 
    select(-c(status_comment, comments, consultant_address, address1)) |> 
    filter(labno %in% sample_vector) |> 
    collect() |> 
    janitor::clean_names() |> 
    mutate(tissue = as.numeric(tissue)) |> 
    left_join(tissue_types, join_by(tissue == tissue_type_id))
  
  return(output)
  
}