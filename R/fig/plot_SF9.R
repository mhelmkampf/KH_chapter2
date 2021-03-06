#!/usr/bin/env Rscript
# run from terminal:
# Rscript --vanilla R/fig/plot_SF9.R 2_analysis/GxP/50000/
# ===============================================================
# This script produces Suppl. Figure 9 of the study "Ancestral variation,
# hybridization and modularity fuel a marine radiation"
# by Hench, McMillan and Puebla
# ---------------------------------------------------------------
# ===============================================================
# args <- c('2_analysis/GxP/50000/')
# script_name <- "R/fig/plot_SF9.R"
args <- commandArgs(trailingOnly = FALSE)
# setup -----------------------
library(GenomicOriginsScripts)
library(hypoimg)

cat('\n')
script_name <- args[5] %>%
  str_remove(.,'--file=')

plot_comment <- script_name %>%
  str_c('mother-script = ',getwd(),'/',.)

args <- process_input(script_name, args)
# config -----------------------
gxp_path <- as.character(args[1])

# configure which gxp data to load
trait_tib  <- tibble(file = dir(gxp_path) %>% .[str_detect(.,"Bars|Peduncle|Snout")]) %>%
  mutate(prep = file) %>%
  separate(prep , into = c("trait", "model_type", "win", "step", "filetype", "zip"),
           sep = "\\.") %>%
  select(file, trait, model_type) %>%
  mutate(path = gxp_path)

# load gxp data
data <- pmap_dfr(trait_tib,get_gxp_both_models)

# compose final figure
p <- data %>%
  ggplot(aes(x = gpos, y = AVG_p_wald))+
  # add gray/white LGs background
  geom_hypo_LG()+
  # add gxp data points
  geom_point(color = plot_clr, size = .3)+
  # set axis layout
  scale_x_hypo_LG()+
  scale_fill_hypo_LG_bg()+
  # set axis titles
  labs(y = expression(G~x~P~(average~italic(p)[wald])))+
  # general plot structure separated by model type and trait
  facet_grid(trait+model_type ~ ., scales = "free_y")+
  # general plot layout
  theme_hypo()

# export final figure
hypo_save(filename = "figures/SF9.png",
       plot = p,
       width = 11,
       height = 7,
       dpi = 600,
       type = "cairo",
       comment = plot_comment)
