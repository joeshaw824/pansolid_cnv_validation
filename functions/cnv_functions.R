# Pan Solid CNV Functions

library(tidyverse)
library(readxl)
library(here)

# Export functions ------------------------------------------------------------------

csv_timestamp <- function(input) {
  write.csv(input,
            file = here::here(paste0(
              "outputs/tables/",
              format(Sys.time(), "%Y_%m_%d_%H_%M_%S"),
              "_",
              deparse(substitute(input)), ".csv"
            )),
            row.names = FALSE
  )
}

dna_db_export <- function(input) {
  write.csv(input,
            file = here::here(paste0(
              "data/dna_db_queries/",
              deparse(substitute(input)), ".csv"
            )),
            row.names = FALSE
  )
}

plot_timestamp <- function(input_plot, input_width = 15, input_height = 12, dpi = 300) {
  
  # Default inputs allow for presenting a plot as half an A4 page
  
  ggsave(
    filename = paste0(
      format(Sys.time(), "%Y_%m_%d_%H_%M_%S"),
      "_",
      deparse(substitute(input_plot)), ".png"
    ),
    plot = input_plot,
    device = "png",
    path = here::here("outputs/plots/"),
    units = "cm",
    width = input_width,
    height = input_height,
    dpi = 300
  )
}


# Data functions --------------------------------------------------------------------

filename_regex <- regex(
  r"[
  (WS\d{6})                                   # Worksheet number
  _
  (\d{8})                                     # Lab number
  (a|b|c|d|)                                  # Suffix
  _
  ([:alnum:]{5,30})                           # Patient name - alphanumeric characters only
  (.xlsx|_S.+.xlsx|_S.+|_CNV_processed.xlsx)  # Ending varies between patients and controls
  ]",
  comments = TRUE
)

parse_filename <- function(input_file, input_group) {
  
  output <- str_extract(input_file, filename_regex,
                        group = input_group)
  
  if (is.na(output)) stop("NA in filename parsing",
                          call. = FALSE)
  
  return(output)
  
}

filename_to_df <- function(file) {
  
  output <- data.frame(
    worksheet = c(parse_filename(file, 1)),
    labno = c(as.character(parse_filename(file, 2))),
    suffix = c(parse_filename(file, 3)),
    patient_name = c(parse_filename(file, 4))) |> 
    mutate(
      labno_suffix = str_c(labno, suffix),
      labno_suffix_worksheet = str_c(labno_suffix, "_", worksheet))
  
  return(output)
  
}

extract_cnv_coordinates <- function(df, cnv_coord_col) {
  
  cnv_coord_regex <- regex(
    r"[
        (|complement\()
        (\d{1,10})     # first coordinate number (1 to 10 digits)
        \.\.           # two full stops
        (\d{1,10})     # second coordinate number (1 to 10 digits)
        ]",
    comments = TRUE
  )
  
  output <- df |> 
    mutate(start = as.numeric(str_extract(string = {{ cnv_coord_col }}, 
                                          pattern = cnv_coord_regex, 
                                          group = 2)),
           end = as.numeric(str_extract(string = {{ cnv_coord_col }}, 
                                        pattern = cnv_coord_regex, 
                                        group = 3))) 
  
  return(output)
  
}

format_repeat_table <- function(df) {
  
  rpt_table <- df |> 
    arrange(labno) |> 
    select(labno_suffix, worksheet, gene, max_region_fold_change,
           st_dev_signal_adjusted_log2_ratios) |>  
    mutate("ERBB2 fold change" = round(max_region_fold_change, 1),
           "Signal adjusted noise" = round(st_dev_signal_adjusted_log2_ratios, 2)) |> 
    select(-c(gene, max_region_fold_change,
              st_dev_signal_adjusted_log2_ratios))

  return(rpt_table)
  
}

extract_cnv_calls <- function(df, input_gene) {
  
  stopifnot("genotype" %in% colnames(df))
  
  dq_regex <- regex(str_c(
    # Group - input gene
    "(",input_gene,")\\s",
    # Group - variable freetype,
    "(amplification\\sdetected|amplification)",
    # Use . for bracket
    "\\s.",
    # Group - variable freetype
    "(Mean\\sDQ|mean\\sDQ|DQ)",
    "\\s",
    # Group - dosage quotient regex
    "(\\d{1,3}|\\d{1,3}\\.\\d{2})",
    "x"))
  
  output <- df |> 
    select(labno, genotype) |> 
    mutate(gene_searched = input_gene,
           gene_match = str_extract(genotype, dq_regex, group = 1),
           gene_dq = as.numeric(str_extract(genotype, dq_regex, group = 4)),
           core_result = ifelse(!is.na(gene_dq), "Amplification", "No call"))
  
  return(output)
  
}

read_summary_tab <- function(file) {
  
  x <- read_excel(path = file,
                  sheet = "Whole Panel UMI Coverage Re...",
                  skip = 1,
                  n_max = 11) |> 
    dplyr::rename(value = "...2")
  
  x_wide <- x |> 
    pivot_wider(names_from = Summary,
                values_from = value) |> 
    # Renaming as >, < and ≥ are removed in clean_names
    # Names shortened for ease of use
    rename(number_target_regions_with_cov_lessthan_138 = `Number of target regions with coverage < 138`,
           total_length_target_regions_with_pos_cov_lessthan_138 = `Total length of target regions containing positions with coverage < 138`,
           total_length_target_region_pos_cov_lessthan_138 = `Total length of target region positions with coverage < 138`,
           total_length_target_region_pos_cov_greaterorequal_138 = `Total length of target region positions with coverage ≥ 138`,
           percent_target_region_pos_cov_greaterorequal_138 = `Percentage of target region positions with coverage ≥ 138 (%)`) |> 
    janitor::clean_names() 
  
  identifiers <- filename_to_df(file)
  
  output <- cbind(identifiers, x_wide)
  
  return(output)
  
}

format_chromosome <- function(df, input_col) {
  
  # Function for reformating chr
  
  output <- df |> 
    mutate(chrom_mod = case_when(
    
      {{ input_col }} %in% c("X", "Y") ~{{ input_col }},
      
      TRUE ~as.character(round(as.numeric({{ input_col }}), 0))),
    
    chromosome_formatted = fct(x = chrom_mod, levels = c("1", "2", "3", "4",
                                               "5",  "6",  "7",  "8",
                                               "9",  "10", "11", "12",
                                               "13", "14", "15", "16",
                                               "17", "18", "19", "20",
                                               "21", "22", "X", "Y")))
  
  return(output)
  
}

read_targeted_region_overview <- function(file) {
  
  # This function reads the table of reads mapped to each chromosome. 
  # The position of this table in the "Whole Panel UMI Coverage" tab varies in each file
  
  x <- read_excel(path = file,
                  sheet = "Whole Panel UMI Coverage Re...")
  
  num_skip <- match("Targeted region overview", x$`Target regions`) + 1
  
  targeted_region_overview <- read_excel(path = file,
                                         sheet = "Whole Panel UMI Coverage Re...",
                                         skip = num_skip,
                                         # 22 autosomes plus 2 sex chromosomes
                                         n_max = 24) |> 
    format_chromosome(input_col = Reference)

  identifiers <- filename_to_df(file)
  
  output <- cbind(identifiers, targeted_region_overview) |> 
    janitor::clean_names()
  
  return(output)
  
}

get_control_coverage <- function(file) {
  
  identifiers <- filename_to_df(file)
  
  df <- read_csv(file) |> 
    janitor::clean_names()
  
  cov <- data.frame(
    "median_coverage" = median(df$coverage),
    "mean_coverage" = mean(df$coverage))
  
  output <- cbind(identifiers, cov)
  
  return(output)
  
}

calculate_target_copies <- function(fold_change, ncc_percent) {
  
  ref_sample_copies <- 200
  
  ncc_fraction <- ncc_percent / 100
  
  sample_total_target_copies <- fold_change * ref_sample_copies
  
  sample_target_copies_in_tumour_cells <- sample_total_target_copies - ((100 * (1-ncc_fraction)) * 2)
  
  sample_target_copies_per_tumour_cell <- sample_target_copies_in_tumour_cells / (100 * ncc_fraction)
  
  return(sample_target_copies_per_tumour_cell)
  
}

true_pos <- "True positive"

true_neg <- "True negative"

false_pos <- "False positive"

false_neg <- "False negative"

classifiers = c(true_pos, true_neg, false_pos, false_neg)

make_confusion_matrix <- function(df, input_column = outcome,
                                  classifiers = c(true_pos, true_neg, false_pos, false_neg),
                                  initial_test,
                                  comparison_test,
                                  positive_state,
                                  negative_state) {
  
  # This function requires an input table with true and false positives and negatives already defined.
  
  true_positives <- nrow(df |> 
                           filter({{ input_column }} == classifiers[1]))
  
  true_negatives <- nrow(df |> 
                           filter({{ input_column }} == classifiers[2]))
  
  false_positives <- nrow(df |> 
                            filter({{ input_column }} == classifiers[3]))
  
  false_negatives <- nrow(df |> 
                            filter({{ input_column }} == classifiers[4]))
  
  tp_char <- as.character(true_positives)
  
  tn_char <- as.character(true_negatives)
  
  fp_char <- as.character(false_positives)
  
  fn_char <- as.character(false_negatives)
  
  conf_matrix <- tribble(
    ~"",               ~"",              ~"",                 ~"",         
    "",                "",               initial_test,        "", 
    "",                "",               positive_state,      negative_state, 
    comparison_test,   positive_state,   tp_char,             fn_char,
    "",                negative_state,   fp_char,             tn_char)
  
  # Overall percent agreement
  
  opa <- round((true_positives + true_negatives) / (true_positives + false_negatives +
                                                      false_positives + true_negatives) * 100, 1)
  
  # Positive percentage agreement
  
  ppa <- round((true_positives) / (true_positives + false_negatives) * 100, 1)
  
  # Negative percentage agreement
  
  npa <- round((true_negatives) / (true_negatives + false_positives) * 100, 1)
  
  return(list(conf_matrix, opa, ppa, npa))
  
}

read_clc_target_calls <- function(file) {
  
  identifiers <- filename_to_df(file)
  
  results <- read_excel(path = file, sheet = 2,
           col_types = c("text", "text", "text",
                         "numeric", "numeric", "numeric",
                         "numeric", "numeric", "numeric",
                         "numeric", "numeric", "numeric",
                         "text", "text",
                         "numeric", "numeric",
                         "text", "text", "text")) |> 
  janitor::clean_names() |> 
  mutate(
    labno = as.character(parse_filename(file, 2)),
    filename = file) |> 
  left_join(identifiers, by = "labno") |> 
  relocate(worksheet, labno, suffix, labno_suffix, patient_name,
           labno_suffix_worksheet)
  
  output <- extract_cnv_coordinates(df = results,
                                    cnv_coord_col = region)
  
  return(output)
  
}

calculate_pooled_sd <- function(df, group = labno, target_col, round_places = 2) {
  
  output_table <- df |> 
    group_by( {{ group }}) |> 
    summarise(sd = sd( {{ target_col }} ),
              max = max( {{ target_col }} ),
              min = min( {{ target_col }} ),
              range = max - min,
              n = n(),
              z = (n-1)*sd^2)
  
  pooled_sd <- round(sqrt(sum(output_table$z) / 
                            (sum(output_table$n))), round_places)
  
  range <- str_c(round(min(output_table$range), round_places), 
                 "-", 
                 round(max(output_table$range), round_places))
  
  return(list(output_table, pooled_sd, range))
  
}

add_dna_db_info <- function(df, 
                            ps_version_df = pansolid_ws_details,
                            extraction_df = sample_extraction_details,
                            gender_df = sample_gender,
                            type_df = sample_types,
                            ncc_df = ncc_collated,
                            tissue_df = sample_tissue_sources_coded,
                            dna_conc_df = sample_dna_concentrations,
                            pathno_df = sample_pathnos,
                            nhsno_df = sample_nhs_no) {
  
  # This is a wrapper function that joins useful information from DNA database onto
  # the results.
  
  if (!"labno" %in% colnames(df) |
      !"worksheet" %in% colnames(df)) { stop("Join columns not present")}
  
  output <- df |> 
    left_join(ps_version_df, by = "worksheet") |> 
    left_join(extraction_df, by = "labno") |> 
    left_join(gender_df, by = "labno") |> 
    left_join(type_df, by = "labno") |> 
    left_join(ncc_df, by = "labno") |> 
    left_join(tissue_df, by = "labno") |> 
    left_join(dna_conc_df, by ="labno") |> 
    left_join(pathno_df, by = "labno") |> 
    left_join(nhsno_df, by = "labno")
  
  return(output)
  
}

add_case_group <- function(df) {
  
  stopifnot("patient_name" %in% colnames(df))
  
  output <- df |> 
    mutate(sample_group = "case",
           sample_subgroup = case_when(
             
             patient_name %in% grep(pattern = "seraseq", x = patient_name,
                                    ignore.case = TRUE, value = TRUE) ~"SeraCare reference material",
             
             TRUE ~"Patient FFPE sample"))
  
  return(output)
  
}

# Processed Excel functions ---------------------------------------------------------

get_full_tbl <- function(file) {
  
  full_tbl <- read_excel(path = file,
                         sheet = "Amplifications",
                         col_names = FALSE) |> 
    janitor::clean_names()
  
  return(full_tbl)
  
}

add_identifiers <- function(file, tbl) {
  
  identifiers <- filename_to_df(file)
  
  labno <- parse_filename(file, 2)
  
  output <- tbl |> 
    mutate(labno = labno, 
           file = file) |>  
    left_join(identifiers, by = "labno") |> 
    relocate(worksheet, labno, suffix, patient_name, 
             labno_suffix, labno_suffix_worksheet, file)
  
  return(output)
  
}

read_pos_cnv_results <- function(file) {
  
  full_tbl <- get_full_tbl(file)

  pos_cnv_tbl_row <- match("Positive CNV results", full_tbl$x1)
  
  na_vector <- which(is.na(full_tbl$x1))
  
  first_na_after_pos_cnv_tbl <- min(na_vector[na_vector > pos_cnv_tbl_row])
  
  size_pos_cnv_tbl <- (first_na_after_pos_cnv_tbl - pos_cnv_tbl_row) - 1
  
  pos_cnv_tbl <- read_excel(path = file,
                            sheet = "Amplifications",
                            skip = pos_cnv_tbl_row,
                            n_max = size_pos_cnv_tbl,
                            col_types = c("text", "text", "text", 
                                          "numeric", "text", "numeric",
                                          "numeric","numeric")) |> 
    janitor::clean_names() 
  
  pos_cnv_coord <- extract_cnv_coordinates(df = pos_cnv_tbl, 
                                           cnv_coord_col = cnv_co_ordinates)
  
  if (nrow(pos_cnv_coord) == 0) {
    
    pos_cnv_coord <- data.frame(
      "gene" = "no positive calls",
      "chromosome" = "",
      "cnv_co_ordinates" = "",
      "cnv_length" = 0,
      "consequence" = "no call",
      "fold_change" = 0,
      "p_value" = 0,
      "no_targets" = 0,
      "start" = 0,
      "end" = 0)
    
  }
  
  output <- add_identifiers(file, pos_cnv_coord)
  
  return(output)
  
}

read_all_amp_genes_results <- function(file) {

  full_tbl <- get_full_tbl(file)
  
  gene_table_row_start <- match("All amplification genes", full_tbl$x1)
  
  gene_tbl <- read_excel(path = file,
                  sheet = "Amplifications",
                  skip = gene_table_row_start,
                  n_max = 9) |> 
    janitor::clean_names() 
  
  output <- add_identifiers(file, gene_tbl)
  
  return(output)
  
}

read_stdev_results <- function(file) {
  
  full_tbl <- get_full_tbl(file)
  
  stdev_start <- match("StDev Signal-adjusted Log2 Ratios", full_tbl$x1) - 1
  
  stdev <- read_excel(path = file,
                  sheet = "Amplifications",
                  skip = stdev_start,
                  n_max = 1) |> 
    janitor::clean_names()
  
  output <- add_identifiers(file, stdev)
  
  return(output)
  
}
  
# Primers ---------------------------------------------------------------------------

grch38_primers <- read_csv(file =
                             here::here("data/primers/CDHS-40079Z-11284.primer3_Converted.csv"),
                           show_col_types = FALSE) |> 
  janitor::clean_names()

grch38_primer_coordinates <- extract_cnv_coordinates(df = grch38_primers,
                                                     cnv_coord_col = region)

# Genes and exons -------------------------------------------------------------------

transcript_regex <- regex(
  r"(
  .+
  (ENST\d{11})
  .csv
  )",
  comments = TRUE
)

read_ensembl_exon_table <- function(filename) {
  
  transcript_id <- str_extract(string = filename, 
                               pattern = transcript_regex,
                               group = 1)
  
  table <- read_csv(file = here::here(filename),
                    show_col_types = FALSE) |> 
    janitor::clean_names() |> 
    filter(!is.na(no)) |> 
    rename(exon = no) |> 
    mutate(transcript = transcript_id) |> 
    relocate(transcript) |> 
    select(-sequence)
  
  return(table)
  
}

gene_labels <- read_excel(path = here::here("data/transcripts/gene_labels.xlsx"),
                        col_types = c("text", "text", "text", "text",
                                      "numeric", "numeric")) |> 
  mutate(y_value = "Genes",
         # Place gene label half-way along gene locus
         start = pmin(gene_start, gene_end) + ((pmax(gene_start, gene_end) - pmin(gene_start, gene_end)) / 2))

transcript_files <- list.files(here::here("data/transcripts/"), full.names = TRUE,
                               pattern = ".csv")

all_transcripts <- transcript_files |>
  map(\(transcript_files) read_ensembl_exon_table(
    file = transcript_files
  )) |>
  list_rbind() |> 
  left_join(gene_labels |> 
              select(label, chromosome, transcript_ensembl), join_by(transcript == transcript_ensembl))
  
# Plot colours ----------------------------------------------------------------------

safe_blue <- "#88CCEE"
safe_red <- "#CC6677"
safe_grey <- "#888888"

# Plot functions --------------------------------------------------------------------

# CNV plots can be presented as triptychs: 
# Panel 1) The plot of CNV calls:
    # a) Either with fold change on the y axis (make_fold_change_plot)
    # b) Or with lab number on the y axis (make_labno_plot)
# Panel 2) A plot showing the locations of Qiaseq primers
# Panel 3) A plot showing annotated locations of gene exons

# The aim of these inter-related functions is to allow maximum flexibility and to keep 
# the x axes consistent between the different plots.

get_breaks <- function(interval, plot_xmin, plot_xmax) {
  
  breaks <- seq(plot_xmin, plot_xmax, by = interval)
  
  return(breaks)

}

get_data_for_plot <- function(df, 
                              gene) {
  
  data_for_plot <- df |> 
    filter(gene == {{ gene }})
  
  return(data_for_plot)
  
}

get_plot_xmin <- function(df, buffer) {
  
  plot_xmin <- min(df$start) - buffer
  
  return(plot_xmin)
  
}

get_plot_xmax <- function(df, buffer) {
  
  plot_xmax <- max(df$end) + buffer
  
  return(plot_xmax)
  
}

get_chromosome <- function(gene) {
  
  chromosome <- as.character(gene_labels[gene_labels$label == gene, 2])
  
  stopifnot(chromosome != "character(0)")
  
  return(chromosome)
  
}

make_fold_change_plot <- function(df = pos_cnv_results, 
                                  gene = "ERBB2",
                                  interval = 10000, 
                                  buffer = 5000, 
                                  ymin = 0,
                                  ymax = 40) {
  
  chromosome <- get_chromosome(gene = {{ gene }})
  
  data_for_plot <- get_data_for_plot(df = {{ df }}, 
                    gene = {{ gene }})
  
  plot_xmin <- get_plot_xmin(df = data_for_plot,
                                 buffer = buffer)
  
  plot_xmax <- get_plot_xmax(df = data_for_plot,
                                 buffer = buffer)
  
  fold_change_plot <- ggplot(data_for_plot, aes(x = start, y = fold_change)) +
    
    # Add theme
    theme_bw() +
    theme(axis.text.x = element_blank()) +
    
    # Add CNV calls
    geom_segment(aes(x = start, xend = end, 
                     y = fold_change, yend = fold_change),
                 linewidth = 2,
                 colour = safe_red) +

    # Add x axes
    scale_x_continuous(breaks = get_breaks(interval = {{ interval}},
                                           plot_xmin = {{ plot_xmin }},
                                           plot_xmax = {{ plot_xmax }}),
                       minor_breaks = NULL,
                       limits = c({{ plot_xmin }}, {{ plot_xmax }} )) +
    
    scale_y_continuous(limits = c(ymin, ymax)) +
    
    # Add labels
    labs(
      y = "Fold change",
      x = "")
  
  return(list(plot_xmin, plot_xmax, interval, fold_change_plot, chromosome))
  
}

make_labno_plot <- function(df = pos_cnv_results, 
                            gene = "ERBB2",
                            interval = 10000, 
                            buffer = 5000, 
                            yaxis = labno) {
  
  chromosome <- get_chromosome(gene = {{ gene }})
  
  data_for_plot <- get_data_for_plot(df = {{ df }}, 
                                     gene = {{ gene }})
  
  max_fold_change <- max(data_for_plot$fold_change)
  
  min_fold_change <- min(data_for_plot$fold_change)
  
  plot_xmin <- get_plot_xmin(df = data_for_plot,
                             buffer = buffer)
  
  plot_xmax <- get_plot_xmax(df = data_for_plot,
                             buffer = buffer)
  
  labno_plot <- ggplot(data_for_plot, aes(x = start, y = {{ yaxis }},
                                                colour = fold_change)) +
    
    # Add theme
    theme_bw() +
    theme(axis.text.x = element_blank()) +
    
    # Add CNV calls
    geom_segment(aes(x = start, xend = end, 
                     y = {{ yaxis }}, yend = {{ yaxis }}),
                 linewidth = 2) +
    
    scale_colour_gradient(low = "#FF9999", 
                          high = "#660000", 
                          limits = c(min_fold_change, max_fold_change),
                          n.breaks = 4) +
    
    # Add x axes
    scale_x_continuous(breaks = get_breaks(interval = {{ interval}},
                                           plot_xmin = {{ plot_xmin }},
                                           plot_xmax = {{ plot_xmax }}),
                       minor_breaks = NULL,
                       limits = c({{ plot_xmin }}, {{ plot_xmax }} )) +
    
    # Add labels
    labs(
      y = "Sample number",
      x = "",
      colour = "Fold change")
  
  return(list(plot_xmin, plot_xmax, interval, labno_plot, chromosome))
  
}

make_primer_plot <- function(plot_xmin, plot_xmax, interval, chromosome) {
  
  primers_filtered <- grch38_primer_coordinates |> 
    mutate(y_value = "Primers") |> 
    filter(chromosome == {{ chromosome }} ) |> 
    filter(start >= {{ plot_xmin }} & end <= {{ plot_xmax }} )
  
  output <-  ggplot(primers_filtered, aes(x = start, y = y_value)) +
    geom_point(pch = 21) +
    theme_bw() +
    theme(axis.text.x = element_blank()) +
    scale_x_continuous(breaks = get_breaks(interval = {{ interval}},
                                           plot_xmin = {{ plot_xmin }},
                                           plot_xmax = {{ plot_xmax }}),
                       minor_breaks = NULL,
                       limits = c({{ plot_xmin }}, {{ plot_xmax }} )) +
    labs (x = "", y = "")
  
  return(output)
  
}

make_exon_plot <- function(plot_xmin, plot_xmax, interval, chromosome) {
  
  exon_data_for_plot <- all_transcripts |> 
    mutate(y_value = "Exons") |> 
    filter(chromosome == {{ chromosome }}) |> 
    filter(start >= {{ plot_xmin }} & end <= {{ plot_xmax }})
  
  labels_for_plot <- gene_labels |> 
    filter(chromosome == {{ chromosome }} ) |> 
    filter(start >= {{ plot_xmin }} & start <= {{ plot_xmax }})
  
  output <- ggplot(exon_data_for_plot, 
                   aes(x = start, y = y_value)) +
    
    geom_segment(aes(x = start, xend = end, 
                     y = y_value, yend = y_value),
                 linewidth = 5) +
    
    theme_bw() +
    
    scale_x_continuous(breaks = get_breaks(interval = {{ interval}},
                                           plot_xmin = {{ plot_xmin }},
                                           plot_xmax = {{ plot_xmax }}),
                       minor_breaks = NULL,
                       limits = c({{ plot_xmin }}, {{ plot_xmax }} )) +
    
    scale_y_discrete(limits = rev) +
    
    theme(axis.text.x = element_text(angle = 90, vjust = 0.5)) +
    
    labs(y = "", x = str_c("Genome coordinate (GRCh38) Chr", 
                           chromosome)) +
    
    geom_label(data = labels_for_plot, label = labels_for_plot$label)
  
  return(output)
  
}

make_cnv_triptych <- function(input_plot) {
 
  # This function is a wrapper which takes the outputs of either the 
  # make_fold_change_plot or make_labno_plot functions
  
  plot_xmin <- input_plot[[1]]
  
  plot_xmax <- input_plot[[2]]
  
  interval <- input_plot[[3]]
  
  main_plot <- input_plot[[4]]
  
  chromosome <- input_plot[[5]]

  primer_plot <- make_primer_plot(plot_xmin = {{ plot_xmin }}, 
                                  plot_xmax = {{ plot_xmax }},
                                  interval = {{ interval }},
                                  chromosome = {{ chromosome }})
  
  exon_plot <- make_exon_plot(plot_xmin = {{ plot_xmin }}, 
                              plot_xmax = {{ plot_xmax }},
                              interval = {{ interval }},
                              chromosome = {{ chromosome }})
  
  triptych <- (main_plot / primer_plot / exon_plot) +
    plot_layout(
      heights = c(6, 1, 2)
    )
  
  return(triptych)
  
}

draw_lod_gene_plot <- function(df, chromosome, gene) {
  
  plot_limit_of_detection <- df |> 
    filter(chromosome == {{ chromosome }}) |> 
    ggplot(aes(x = start, y = fold_change_adjusted)) +
    geom_point(pch = 21) +
    geom_point(data = df |> 
                 filter(name == {{ gene }}), fill = safe_red, 
               pch = 21, size = 2) +
    facet_wrap(~ncc) +
    theme_bw() +
    scale_y_continuous(limits = c(-3, 6),
                       breaks = c(-3, -2, -1, 0, 1, 2, 2.8, 4, 5, 6)) +
    geom_hline(yintercept = 2.8, linetype = "dashed") +
    labs(x = str_c("Chromosome ", {{ chromosome }}),
         y = "Target fold change",
         title = str_c("Limit of detection results: ", {{ gene }}),
         caption = "Seracare +12 copies control spiked into Seracare wild type control",
         subtitle = str_c({{ gene }}, " in red"))
  
  return(plot_limit_of_detection)
  
}

# ddPCR functions -------------------------------------------------------------------

read_biorad_csv <- function(worksheet) {
  
  output <- read_csv(here::here(str_c("data/ddpcr_data/", worksheet)), 
              col_types = cols(
                "Well" = "c",
                "ExptType" = "c",
                "Experiment" = "c",
                "Sample" = "c",
                "TargetType" = "c",
                "Target" = "c",
                "Status" = "c",
                "Concentration" = "d",
                "Supermix" = "c",
                "CopiesPer20uLWell" = "d",
                "TotalConfMax" = "d",
                "TotalConfMin" = "d",
                "PoissonConfMax" = "d",
                "PoissonConfMin" = "d",
                "Positives" = "i",
                "Negatives" = "i",
                "Ch1+Ch2+" = "i",
                "Ch1+Ch2-" = "i",
                "Ch1-Ch2+" = "i",
                "Ch1-Ch2-" = "i",
                "Linkage"  = "d",
                "AcceptedDroplets" = "i",
                "CNV" = "d",
                "TotalCNVMax" = "d",
                "TotalCNVMin" = "d",
                "PoissonCNVMax" = "d",
                "PoissonCNVMin" = "d",
                "FractionalAbundance" = "d",
                "TotalFractionalAbundanceMax" = "d",
                "TotalFractionalAbundanceMin" = "d",
                "PoissonFractionalAbundanceMax" = "d",
                "PoissonFractionalAbundanceMin" = "d",
                "ReferenceAssayNumber" = "d",
                "TargetAssayNumber" = "d",
                "Threshold" = "d",
                "MeanAmplitudeofPositives" = "d",
                "MeanAmplitudeofNegatives" = "d",
                "MeanAmplitudeTotal" = "d",
                "ExperimentComments" = "c",
                "MergedWells" = "c",
                "TotalConfMax68" = "d",
                "TotalConfMin68" = "d",
                "PoissonConfMax68" = "d",
                "PoissonConfMin68" = "d",
                "TotalCNVMax68" = "d",
                "TotalCNVMin68" = "d",
                "PoissonCNVMax68" = "d",
                "PoissonCNVMin68" = "d",
                "PoissonCNVMin68" = "d",
                "PoissonRatioMax68" = "d",
                "TotalRatioMin68" = "d",
                "TotalFractionalAbundanceMax68" = "d",
                "TotalFractionalAbundanceMin68" = "d",
                "PoissonFractionalAbundanceMax68" = "d",                
                "PoissonFractionalAbundanceMin68" = "d")) |> 
  janitor::clean_names() |> 
  mutate(sample_well = str_c(sample, "_", well),
         worksheet = worksheet,
         labno = sample)
  
  return(output)
  
}     

draw_ddpcr_cnv_plot <- function(worksheet_df, y_max = 10) {
  
  output <- ggplot(worksheet_df, aes(x = sample_well, y = cnv)) +
    geom_point(aes(colour = gene), size = 3) +
    geom_errorbar(aes(ymin = poisson_cnv_min, max = poisson_cnv_max)) +
    theme_bw() +
    theme(axis.text.x = element_text(angle = 90)) +
    scale_y_continuous(breaks = c(1:y_max), limits = c(0, y_max),
                       minor_breaks = c(1:y_max)) +
    labs(y = "Copy number", x = "") +
    geom_hline(yintercept = 2, linetype = "dashed")

  return(output)
  
}


# PanSolid functions ----------------------------------------------------------------

join_pansolid_submission_sheets <- function() {
  
  # This functions wrangles and binds the various submission sheets used for organising
  # the PanSolid workflow
  
  # The sample_id field has some surprises. Example: 23024772 has a degree sign (°)
  # entered after it which is invisible in Excel and R.
  
  pansolid_submission_2023 <- read_excel(path = here::here("data/dna_submission_sheets/DNA PanSolid QIAseq Submission Sheet 2023.xlsx")) |> 
    janitor::clean_names() |> 
    rename(stock_qubit = stock_qubit_ng_m_l) |> 
    mutate(submission_sheet = "2023",
           labno = str_extract(string = sample_id, pattern = "\\d{8}")) |> 
    select(date_submitted, labno, sample_name,
           panel, enrichment, stock_qubit, submission_sheet)
  
  pansolid_submission_2024 <- read_excel(path = here::here("data/dna_submission_sheets/PanSolid Submission sheet 2024.xlsx"),
                                         sheet = "PanSolid samples") |> 
    janitor::clean_names()  |> 
    rename(stock_qubit = stock_qubit_ng_m_l) |> 
    mutate(submission_sheet = "2024",
           labno = str_extract(string = sample_id, pattern = "\\d{8}")) |> 
    select(date_submitted, labno, sample_name,
           panel, enrichment, stock_qubit, submission_sheet)
  
  # Pansolid began in 2022 so the initial runs were recorded on the Qiaseq spreadsheet
  pansolid_submission_2022 <- read_excel(path = here::here("data/dna_submission_sheets/QIAseq DNA PanSolid Sample Submission 2022.xlsx")) |> 
    janitor::clean_names() |> 
    rename(date_submitted = date_sample_submitted,
           stock_qubit = stock_qubit_ng_m_l) |> 
    mutate(submission_sheet = "2022",
           labno = str_extract(string = sample_id, pattern = "\\d{8}")) |> 
    select(date_submitted, labno, sample_name,
           panel, enrichment, stock_qubit, submission_sheet)
  
  output <- rbind(pansolid_submission_2024,
                  pansolid_submission_2023,
                  pansolid_submission_2022)
  
  return(output)
  
}
