# Analiza do projektu ASC: szereg niesezonowy i sezonowy.
# Kod jest zapisany proceduralnie, bez własnych funkcji pomocniczych.
options(stringsAsFactors = FALSE)
dir.create(file.path(getwd(), "Rlib"), showWarnings = FALSE)
.libPaths(c(file.path(getwd(), "Rlib"), .libPaths()))
library(jsonlite)
needed <- c("S7", "scales", "gtable", "ggplot2", "vctrs", "cli", "glue", "rlang",
            "lifecycle", "farver", "labeling", "R6", "viridisLite",
            "xts", "zoo", "quadprog", "TTR", "quantmod",
            "tseries", "forecast", "urca", "lmtest", "jsonlite")

to_install <- needed[!needed %in% rownames(installed.packages())]
if (length(to_install) > 0) {
  install.packages(to_install, lib = file.path(getwd(), "Rlib"))
}
library(scales)
library(gtable)
library(forecast)
library(urca)
library(tseries)
library(lmtest)
library(jsonlite)

# Ścieżki projektu i katalogi wynikowe.
root_dir <- getwd()  # uruchamiać z katalogu repozytorium
setwd(root_dir)
latex_dir <- file.path(root_dir, "latex")
fig_dir <- file.path(latex_dir, "figures")
tab_dir <- file.path(latex_dir, "tables")
out_dir <- file.path(latex_dir, "wyniki")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# Funkcja zapisuje wykresy przez Cairo, żeby polskie znaki były poprawnie osadzane w PDF-ach.
pdf <- function(file, width = 7, height = 7, ...) {
  grDevices::cairo_pdf(filename = file, width = width, height = height,
                       family = "Arial", ...)
}

# =============================================================================
# SZEREG NIESEZONOWY: ŚREDNIOROCZNA TEMPERATURA W POLSCE
# =============================================================================

# Dane 1901--2024 pochodzą z World Bank CCKP, seria CRU cru-x0.5.
# Rok 2025 dokładamy z pliku IMGW.
temp_json_file <- file.path(root_dir, "niesezonowy", "dane", "worldbank.json")
temp_json <- jsonlite::read_json(temp_json_file, simplifyVector = FALSE)
temp_wb <- data.frame(
  rok = as.integer(substr(names(temp_json$data$POL), 1, 4)),
  temp = as.numeric(temp_json$data$POL)
)
temp_wb <- temp_wb[temp_wb$rok >= 1901 & temp_wb$rok <= 2024, ]

temp_imgw_file <- file.path(root_dir, "niesezonowy", "dane", "sredniorocznaT.csv")
temp_imgw <- read.delim(temp_imgw_file, dec = ",", fileEncoding = "UTF-8")
temp_2025 <- temp_imgw[temp_imgw$rok == 2025, c("rok", "temp")]

temp_raw <- rbind(temp_wb, temp_2025)
temp_raw <- temp_raw[order(temp_raw$rok), ]
stopifnot(identical(temp_raw$rok, 1901:2025), !anyNA(temp_raw$temp))
temp_ts <- ts(temp_raw$temp, start = min(temp_raw$rok), frequency = 1)
message("Wczytano szereg temperatury: ", length(temp_ts), " obserwacji.")

# Wykres szeregu czasowego.
temp_szereg_path <- file.path(fig_dir, "temp_szereg.pdf")
pdf(temp_szereg_path, width = 7, height = 4.2)
plot(temp_ts, type = "l", col = "black",
     main = "Średnioroczna temperatura w Polsce",
     xlab = "Rok", ylab = "Temperatura [st. C]")
grid()
invisible(dev.off())
message("Zapisano wykres: ", normalizePath(temp_szereg_path, winslash = "/", mustWork = FALSE))

# Wygładzenie średnią ruchomą i trend liniowy.
temp_ma3 <- stats::filter(temp_ts, sides = 2, filter = rep(1 / 3, 3))
temp_lm <- lm(as.numeric(temp_ts) ~ as.numeric(time(temp_ts)))
temp_trend <- ts(fitted(temp_lm), start = start(temp_ts), frequency = 1)

temp_trend_path <- file.path(fig_dir, "temp_trend.pdf")
pdf(temp_trend_path, width = 7, height = 4.2)
plot(temp_ts, type = "l", col = "black",
     main = "Trend średniorocznej temperatury",
     xlab = "Rok", ylab = "Temperatura [st. C]")
lines(temp_ma3, col = "blue", lwd = 2, lty = 1)
lines(temp_trend, col = "red", lwd = 2)
legend("topleft", legend = c("szereg", "średnia ruchoma q=1", "trend liniowy"),
       col = c("black", "blue", "red"), lty = c(1, 1, 1),
       bty = "n", cex = 0.8)
grid()
invisible(dev.off())
message("Zapisano wykres: ", normalizePath(temp_trend_path, winslash = "/", mustWork = FALSE))

# Dekompozycja szeregu temperatury bez sztucznego panelu sezonowości.
# Dla danych rocznych pokazujemy szereg, trend i składnik losowy jako różnicę.
temp_decomp_random <- temp_ts - temp_ma3
temp_decomp_path <- file.path(fig_dir, "temp_dekompozycja.pdf")
pdf(temp_decomp_path, width = 7, height = 5.4)
par(mfrow = c(3, 1), mar = c(3, 4, 2.2, 1))
plot(temp_ts, type = "l",
     main = "Szereg temperatury",
     xlab = "Rok", ylab = "Temperatura [st. C]")
plot(temp_ma3, type = "l",
     main = "Trend",
     xlab = "Rok", ylab = "Trend")
plot(temp_decomp_random, type = "l",
     main = "Składnik losowy",
     xlab = "Rok", ylab = "Reszty")
abline(h = 0, col = "red", lty = 2)
par(mfrow = c(1, 1), mar = c(5, 4, 4, 2) + 0.1)
invisible(dev.off())
message("Zapisano wykres: ", normalizePath(temp_decomp_path, winslash = "/", mustWork = FALSE))

# Wykres "lockout" nie narzuca sztucznie zerowego składnika sezonowego ani żadnego okresu.
# Trend i wolniejsze wahania wyznaczamy wygładzaniem supsmu, a szum jest resztą po tych składnikach.
temp_lockout_years <- as.integer(time(temp_ts))
temp_lockout_values <- as.numeric(temp_ts)
temp_lockout_trend <- supsmu(temp_lockout_years, temp_lockout_values,
                             bass = 8)$y
temp_lockout_detrended <- temp_lockout_values - temp_lockout_trend
temp_lockout_cycle <- supsmu(temp_lockout_years, temp_lockout_detrended,
                             bass = 4)$y
temp_lockout_random <- temp_lockout_detrended - temp_lockout_cycle
temp_lockout_path <- file.path(fig_dir, "temp_dekompozycja_lockout.pdf")
temp_lockout_actual_path <- temp_lockout_path
temp_lockout_pdf <- try(pdf(temp_lockout_actual_path, width = 7, height = 7.5),
                        silent = TRUE)
if (inherits(temp_lockout_pdf, "try-error")) {
  # Gdy plik PDF jest otwarty w podglądzie, zapisujemy kopię roboczą zamiast przerywać skrypt.
  temp_lockout_actual_path <- file.path(fig_dir, "temp_dekompozycja_lockout_new.pdf")
  pdf(temp_lockout_actual_path, width = 7, height = 7.5)
}
par(mfrow = c(4, 1), mar = c(3, 4, 2.2, 1))
plot(temp_lockout_years, as.numeric(temp_ts), type = "l",
     main = "Szereg temperatury",
     xlab = "Rok", ylab = "Temperatura [st. C]")
grid()
plot(temp_lockout_years, temp_lockout_trend, type = "l", col = "red", lwd = 2,
     main = "Trend STL",
     xlab = "Rok", ylab = "Trend")
grid()
plot(temp_lockout_years, temp_lockout_cycle, type = "l", col = "blue", lwd = 2,
     main = "Składnik cykliczny bez zadanego okresu",
     xlab = "Rok", ylab = "Cykliczność")
abline(h = 0, col = "red", lty = 2)
grid()
plot(temp_lockout_years, temp_lockout_random, type = "l",
     main = "Składnik losowy",
     xlab = "Rok", ylab = "Szum")
abline(h = 0, col = "red", lty = 2)
grid()
par(mfrow = c(1, 1), mar = c(5, 4, 4, 2) + 0.1)
invisible(dev.off())
message("Zapisano wykres: ", normalizePath(temp_lockout_actual_path, winslash = "/", mustWork = FALSE))

# Podział próby: model uczymy do 2023, testujemy na latach 2024--2025.
temp_train <- window(temp_ts, end = 2023)
temp_test <- window(temp_ts, start = 2024)

# Model Holta z pakietu forecast dla szeregu rocznego bez sezonowości.
temp_holt_train <- holt(temp_train, h = length(temp_test))
temp_hw_pred <- temp_holt_train$mean
temp_holt_final <- holt(temp_ts, h = 3)
temp_hw_fc <- temp_holt_final$mean

# Dodatkowe modele ekstrapolacyjne z wzorców ASC05--ASC06 dla szeregu niesezonowego.
# Każdy model estymujemy na tej samej próbie uczącej, a jako kryterium błędu
# ex post przyjmujemy zgodność prognoz z obserwacjami z lat 2024--2025.
temp_extrap_train_models <- list(
  "Średnia" = meanf(temp_train, h = length(temp_test)),
  "Naiwny" = naive(temp_train, h = length(temp_test)),
  "Błądzenie losowe z dryfem" = rwf(temp_train, drift = TRUE, h = length(temp_test)),
  "SES" = ses(temp_train, h = length(temp_test)),
  "Holt" = temp_holt_train
)

# Modele końcowe wykorzystują cały dostępny szereg i służą do prognozy na kolejne lata.
temp_extrap_final_models <- list(
  "Średnia" = meanf(temp_ts, h = 3),
  "Naiwny" = naive(temp_ts, h = 3),
  "Błądzenie losowe z dryfem" = rwf(temp_ts, drift = TRUE, h = 3),
  "SES" = ses(temp_ts, h = 3),
  "Holt" = temp_holt_final
)

# Porównanie jakości prognoz out-of-sample oraz dopasowania in-sample.
temp_extrap_compare <- data.frame(
  model = names(temp_extrap_train_models),
  AIC = NA_real_,
  BIC = NA_real_,
  ME = NA_real_,
  MAE = NA_real_,
  RMSE = NA_real_,
  MAPE = NA_real_,
  Fit_MAE = NA_real_,
  Fit_RMSE = NA_real_,
  Fit_MAPE = NA_real_
)
for (i in seq_along(temp_extrap_train_models)) {
  temp_model_name <- names(temp_extrap_train_models)[i]
  temp_model <- temp_extrap_train_models[[i]]
  temp_err <- as.numeric(temp_test) - as.numeric(temp_model$mean)
  temp_fit_err <- as.numeric(temp_train) - as.numeric(fitted(temp_model))
  temp_extrap_compare$ME[i] <- mean(temp_err)
  temp_extrap_compare$MAE[i] <- mean(abs(temp_err))
  temp_extrap_compare$RMSE[i] <- sqrt(mean(temp_err^2))
  temp_extrap_compare$MAPE[i] <- mean(abs(temp_err / as.numeric(temp_test))) * 100
  temp_extrap_compare$Fit_MAE[i] <- mean(abs(temp_fit_err), na.rm = TRUE)
  temp_extrap_compare$Fit_RMSE[i] <- sqrt(mean(temp_fit_err^2, na.rm = TRUE))
  temp_extrap_compare$Fit_MAPE[i] <- mean(abs(temp_fit_err / as.numeric(temp_train)), na.rm = TRUE) * 100
  if (!is.null(temp_model$model$aic)) {
    temp_extrap_compare$AIC[i] <- temp_model$model$aic
    temp_extrap_compare$BIC[i] <- temp_model$model$bic
  }
}
temp_extrap_compare <- temp_extrap_compare[order(temp_extrap_compare$RMSE,
                                                 temp_extrap_compare$MAE), ]
rownames(temp_extrap_compare) <- NULL
temp_extrap_best_error <- temp_extrap_compare$model[1]
temp_extrap_best_fit <- temp_extrap_compare$model[which.min(temp_extrap_compare$Fit_RMSE)]
print(temp_extrap_compare)

# Wykres porównuje wartości rzeczywiste z wartościami dopasowanymi modelu Holta w próbie uczącej.
temp_holt_fit_path <- file.path(fig_dir, "temp_holt_dopasowanie.pdf")
pdf(temp_holt_fit_path, width = 7, height = 4.2)
plot(temp_train, type = "l", col = "black",
     main = "Dopasowanie modelu Holta dla temperatury",
     xlab = "Rok", ylab = "Temperatura [st. C]",
     ylim = range(c(temp_train, fitted(temp_holt_train)), na.rm = TRUE))
lines(fitted(temp_holt_train), col = "blue", lwd = 2)
legend("topleft", legend = c("wartości rzeczywiste", "wartości modelu"),
       col = c("black", "blue"), lty = c(1, 1),
       bty = "n", cex = 0.8)
grid()
invisible(dev.off())
message("Zapisano wykres: ", normalizePath(temp_holt_fit_path, winslash = "/", mustWork = FALSE))

# Modele ARIMA estymowane jawnie, jak we wzorcach.
# Kandydaci przyjmują d = 0, q = 1 lub 3 oraz p wskazywane przez ACF/PACF: 1, 3, 4 i 6.
temp_arima_specs <- data.frame(
  model = c("ARIMA(1,0,0)", "ARIMA(1,0,1)", "ARIMA(1,0,2)",
            "ARIMA(2,0,0)", "ARIMA(2,0,1)", "ARIMA(2,0,2)",
            "ARIMA(4,0,0)", "ARIMA(4,0,1)", "ARIMA(4,0,2)",
            "ARIMA(5,0,0)", "ARIMA(5,0,1)", "ARIMA(5,0,2)"),
  p = c(1, 1, 1,
        2, 2, 2,
        4, 4, 4,
        5, 5, 5),
  d = rep(0, 12),
  q = c(0, 1, 2,
        0, 1, 2,
        0, 1, 2,
        0, 1, 2)
)
temp_arima_train_models <- vector("list", nrow(temp_arima_specs))
temp_arima_ok <- rep(FALSE, nrow(temp_arima_specs))
for (i in seq_len(nrow(temp_arima_specs))) {
  # Każdy model estymujemy na próbie uczącej, aby kryteria dotyczyły tego samego zakresu danych.
  temp_fit <- try(arima(temp_train,
                        order = c(temp_arima_specs$p[i],
                                  temp_arima_specs$d[i],
                                  temp_arima_specs$q[i]),
                        method = "ML"),
                  silent = TRUE)
  if (!inherits(temp_fit, "try-error")) {
    temp_arima_train_models[[i]] <- temp_fit
    temp_arima_ok[i] <- TRUE
  }
}
temp_arima_compare <- data.frame(
  model = temp_arima_specs$model[temp_arima_ok],
  p = temp_arima_specs$p[temp_arima_ok],
  d = temp_arima_specs$d[temp_arima_ok],
  q = temp_arima_specs$q[temp_arima_ok],
  AIC = sapply(temp_arima_train_models[temp_arima_ok], AIC),
  BIC = sapply(temp_arima_train_models[temp_arima_ok], BIC)
)
# Dla każdego kandydata sprawdzamy autokorelację reszt testem Ljunga-Boxa.
temp_arima_compare$LB_lag <- NA_integer_
temp_arima_compare$LB_stat <- NA_real_
temp_arima_compare$LB_p <- NA_real_
for (i in seq_len(nrow(temp_arima_compare))) {
  temp_fit <- temp_arima_train_models[[which(temp_arima_specs$model == temp_arima_compare$model[i])]]
  temp_fitdf <- length(temp_fit$coef)
  temp_lag <- 10
  temp_lb_candidate <- Box.test(residuals(temp_fit), lag = temp_lag,
                                type = "Ljung-Box", fitdf = temp_fitdf)
  temp_arima_compare$LB_lag[i] <- temp_lag
  temp_arima_compare$LB_stat[i] <- as.numeric(temp_lb_candidate$statistic)
  temp_arima_compare$LB_p[i] <- temp_lb_candidate$p.value
}
temp_arima_compare <- temp_arima_compare[order(temp_arima_compare$AIC), ]
rownames(temp_arima_compare) <- NULL
print(temp_arima_compare)

temp_arima_porownanie_path <- file.path(tab_dir, "temp_arima_porownanie.tex")
temp_arima_porownanie_lines <- c(
  "\\begin{tabular}{lrrrrr}",
  "\\toprule",
  "\\textbf{Model} & \\textbf{AIC} & \\textbf{BIC} & \\textbf{Lag LB} & \\textbf{Stat. LB} & \\textbf{LB p}",
  "\\\\",
  "\\midrule"
)
for (i in seq_len(nrow(temp_arima_compare))) {
  temp_arima_porownanie_lines <- c(
    temp_arima_porownanie_lines,
    paste(temp_arima_compare$model[i], "&",
          formatC(temp_arima_compare$AIC[i], digits = 3, format = "f", decimal.mark = ","), "&",
          formatC(temp_arima_compare$BIC[i], digits = 3, format = "f", decimal.mark = ","), "&",
          temp_arima_compare$LB_lag[i], "&",
          formatC(temp_arima_compare$LB_stat[i], digits = 3, format = "f", decimal.mark = ","), "&",
          formatC(temp_arima_compare$LB_p[i], digits = 3, format = "f", decimal.mark = ",")),
    "\\\\"
  )
}
temp_arima_porownanie_lines <- c(temp_arima_porownanie_lines, "\\bottomrule", "\\end{tabular}")
writeLines(temp_arima_porownanie_lines, temp_arima_porownanie_path, useBytes = TRUE)
message("Zapisano tabelę: ", normalizePath(temp_arima_porownanie_path, winslash = "/", mustWork = FALSE))

temp_arima_best <- temp_arima_compare[1, ]
temp_arima_label <- temp_arima_best$model
temp_arima_train_index <- which(temp_arima_specs$model == temp_arima_label)
temp_arima_train <- temp_arima_train_models[[temp_arima_train_index]]
temp_arima_order <- c(temp_arima_best$p, temp_arima_best$d, temp_arima_best$q)
temp_arima_final <- arima(temp_ts, order = temp_arima_order, method = "ML")

# Wartości modelu ARIMA wyznaczamy jako obserwacje pomniejszone o reszty modelu.
temp_arima_fitted <- ts(as.numeric(temp_ts) - as.numeric(residuals(temp_arima_final)),
                        start = start(temp_ts), frequency = frequency(temp_ts))
temp_arima_fit_path <- file.path(fig_dir, "temp_arima_dopasowanie.pdf")
pdf(temp_arima_fit_path, width = 7, height = 4.2)
plot(temp_ts, type = "l", col = "black",
     main = "Dopasowanie modelu ARIMA dla temperatury",
     xlab = "Rok", ylab = "Temperatura [st. C]",
     ylim = range(c(temp_ts, temp_arima_fitted), na.rm = TRUE))
lines(temp_arima_fitted, col = "red", lwd = 2)
legend("topleft", legend = c("wartości rzeczywiste", "wartości modelu"),
       col = c("black", "red"), lty = c(1, 1),
       bty = "n", cex = 0.8)
grid()
invisible(dev.off())
message("Zapisano wykres: ", normalizePath(temp_arima_fit_path, winslash = "/", mustWork = FALSE))
# Tabela istotności parametrów modelu ARIMA(4,0,1)
library(lmtest)

temp_arima_401 <- arima(temp_train, order = c(4, 0, 1), method = "ML")
temp_arima_401_coef <- coeftest(temp_arima_401)

temp_arima_401_parametry_path <- file.path(tab_dir, "temp_arima_401_parametry.tex")

temp_arima_401_parametry_lines <- c(
  "\\begin{tabular}{lrrrr}",
  "\\toprule",
  "\\textbf{Parametr} & \\textbf{Oszacowanie} & \\textbf{Błąd std.} & \\textbf{z} & \\textbf{p-value} \\\\",
  "\\midrule"
)

for (i in seq_len(nrow(temp_arima_401_coef))) {
  temp_arima_401_parametry_lines <- c(
    temp_arima_401_parametry_lines,
    paste(
      rownames(temp_arima_401_coef)[i], "&",
      formatC(temp_arima_401_coef[i, 1], digits = 3, format = "f", decimal.mark = ","), "&",
      formatC(temp_arima_401_coef[i, 2], digits = 3, format = "f", decimal.mark = ","), "&",
      formatC(temp_arima_401_coef[i, 3], digits = 3, format = "f", decimal.mark = ","), "&",
      formatC(temp_arima_401_coef[i, 4], digits = 3, format = "f", decimal.mark = ","),
      "\\\\"
    )
  )
}

temp_arima_401_parametry_lines <- c(
  temp_arima_401_parametry_lines,
  "\\bottomrule",
  "\\end{tabular}"
)

writeLines(temp_arima_401_parametry_lines, temp_arima_401_parametry_path, useBytes = TRUE)

# Test LR dla sprawdzenia, czy dodanie składnika MA(1) istotnie poprawia ARIMA(4,0,0).
temp_arima_400 <- arima(temp_train, order = c(4, 0, 0), method = "ML")
temp_arima_lr_df <- as.integer(attr(logLik(temp_arima_401), "df") -
                                 attr(logLik(temp_arima_400), "df"))
temp_arima_lr_stat <- 2 * (as.numeric(logLik(temp_arima_401)) -
                             as.numeric(logLik(temp_arima_400)))
temp_arima_lr_p <- pchisq(temp_arima_lr_stat, df = temp_arima_lr_df,
                          lower.tail = FALSE)
temp_arima_lr_wniosek <- ifelse(temp_arima_lr_p < 0.05,
                                "odrzucenie $H_0$", "brak podstaw")
temp_arima_lr_path <- file.path(tab_dir, "temp_arima_lr_400_401.tex")
writeLines(c(
  "\\begin{tabular}{llrrrl}",
  "\\toprule",
  "\\textbf{Model ograniczony} & \\textbf{Model nieograniczony} & \\textbf{df} & \\textbf{LR} & \\textbf{p-value} & \\textbf{Wniosek}",
  "\\\\",
  "\\midrule",
  paste("ARIMA(4,0,0) & ARIMA(4,0,1) &",
        temp_arima_lr_df, "&",
        formatC(temp_arima_lr_stat, digits = 3, format = "f", decimal.mark = ","), "&",
        formatC(temp_arima_lr_p, digits = 3, format = "f", decimal.mark = ","), "&",
        temp_arima_lr_wniosek),
  "\\\\",
  "\\bottomrule",
  "\\end{tabular}"
), temp_arima_lr_path, useBytes = TRUE)
message("Zapisano tabelę: ", normalizePath(temp_arima_lr_path, winslash = "/", mustWork = FALSE))

temp_arima_pred <- predict(temp_arima_train, n.ahead = length(temp_test))$pred
temp_arima_fc <- predict(temp_arima_final, n.ahead = 3)$pred

# Test ADF z kontrolą autokorelacji reszt testem Breuscha-Godfreya.
temp_adf_max_lag <- 6
temp_adf_level_results <- data.frame(lag = 0:temp_adf_max_lag,
                                     stat = NA_real_,
                                     crit5 = NA_real_,
                                     bg_p = NA_real_,
                                     wniosek = NA_character_)
temp_adf_level_models <- vector("list", nrow(temp_adf_level_results))
for (i in seq_len(nrow(temp_adf_level_results))) {
  temp_fit <- ur.df(temp_ts, type = c("drift"),
                    lags = temp_adf_level_results$lag[i])
  temp_adf_level_models[[i]] <- temp_fit
  temp_adf_level_results$stat[i] <- temp_fit@teststat[1]
  temp_adf_level_results$crit5[i] <- temp_fit@cval[1, "5pct"]
  temp_adf_level_results$bg_p[i] <- bgtest(temp_fit@testreg$residuals ~ 1,
                                           order = 1)$p.value
  temp_adf_level_results$wniosek[i] <- ifelse(temp_adf_level_results$stat[i] <
                                                temp_adf_level_results$crit5[i],
                                              "stacjonarny", "niestacjonarny")
}
temp_adf_level_choice <- which(temp_adf_level_results$bg_p >= 0.05)[1]
if (is.na(temp_adf_level_choice)) {
  temp_adf_level_choice <- nrow(temp_adf_level_results)
}
temp_adf_level <- temp_adf_level_models[[temp_adf_level_choice]]
temp_adf_level_lag <- temp_adf_level_results$lag[temp_adf_level_choice]
temp_adf_level_stat <- temp_adf_level_results$stat[temp_adf_level_choice]
temp_adf_level_crit <- temp_adf_level_results$crit5[temp_adf_level_choice]
temp_adf_level_bg_p <- temp_adf_level_results$bg_p[temp_adf_level_choice]
temp_adf_level_wniosek <- temp_adf_level_results$wniosek[temp_adf_level_choice]

# Korelogramy do wyboru rzędów p i q modelu ARIMA.
temp_arima_ident_path <- file.path(fig_dir, "temp_arima_identyfikacja_acf_pacf.pdf")
# Wyższy wykres ułatwia odczyt pojedynczych słupków ACF i PACF.
pdf(temp_arima_ident_path, width = 7, height = 7.5)
par(mfrow = c(2, 1))
temp_arima_ident <- temp_ts
temp_acf_ident <- acf(temp_arima_ident, lag.max = 36, plot = FALSE, na.action = na.pass)
temp_acf_lags <- as.numeric(temp_acf_ident$lag[-1])
temp_acf_values <- as.numeric(temp_acf_ident$acf[-1])
temp_acf_ci <- qnorm(0.975) / sqrt(length(temp_arima_ident))
temp_acf_ylim <- range(c(temp_acf_values, -temp_acf_ci, temp_acf_ci), na.rm = TRUE)
plot(temp_acf_lags, temp_acf_values, type = "n",
     main = "ACF szeregu temperatury",
     xlab = "Opóźnienie", ylab = "Autokorelacja",
     ylim = temp_acf_ylim, xlim = range(temp_acf_lags))
rect(min(temp_acf_lags) - 0.5, -temp_acf_ci, max(temp_acf_lags) + 0.5, temp_acf_ci,
     col = "grey75", border = NA)
grid(col = "grey90")
abline(h = 0, col = "black")
segments(temp_acf_lags, 0, temp_acf_lags, temp_acf_values, col = "#174A73", lwd = 1.4)
points(temp_acf_lags, temp_acf_values, pch = 16, col = "#174A73", cex = 0.9)
mtext("Szary pas: 95% granice istotności", side = 1, line = 3, adj = 0, cex = 0.75)

temp_pacf_ident <- pacf(temp_arima_ident, lag.max = 36, plot = FALSE, na.action = na.pass)
temp_pacf_lags <- as.numeric(temp_pacf_ident$lag)
temp_pacf_values <- as.numeric(temp_pacf_ident$acf)
temp_pacf_ci <- qnorm(0.975) / sqrt(length(temp_arima_ident))
temp_pacf_ylim <- range(c(temp_pacf_values, -temp_pacf_ci, temp_pacf_ci), na.rm = TRUE)
plot(temp_pacf_lags, temp_pacf_values, type = "n",
     main = "PACF szeregu temperatury",
     xlab = "Opóźnienie", ylab = "Autokorelacja cząstkowa",
     ylim = temp_pacf_ylim, xlim = range(temp_pacf_lags))
rect(min(temp_pacf_lags) - 0.5, -temp_pacf_ci, max(temp_pacf_lags) + 0.5, temp_pacf_ci,
     col = "grey75", border = NA)
grid(col = "grey90")
abline(h = 0, col = "black")
segments(temp_pacf_lags, 0, temp_pacf_lags, temp_pacf_values, col = "#174A73", lwd = 1.4)
points(temp_pacf_lags, temp_pacf_values, pch = 16, col = "#174A73", cex = 0.9)
mtext("Szary pas: 95% granice istotności", side = 1, line = 3, adj = 0, cex = 0.75)
par(mfrow = c(1, 1))
invisible(dev.off())
message("Zapisano wykres: ", normalizePath(temp_arima_ident_path, winslash = "/", mustWork = FALSE))

# Diagnostyka reszt ARIMA.
temp_arima_fitdf <- length(temp_arima_final$coef)
temp_lb_lag <- 10
temp_lb <- Box.test(residuals(temp_arima_final), lag = temp_lb_lag,
                    type = "Ljung-Box", fitdf = temp_arima_fitdf)
temp_jb <- jarque.bera.test(residuals(temp_arima_final))

temp_arima_diag_path <- file.path(fig_dir, "temp_arima_diagnostyka.pdf")
# Trzy panele diagnostyczne wymagają większej wysokości, żeby korelogram był czytelny.
pdf(temp_arima_diag_path, width = 7, height = 8)
par(mfrow = c(3, 1))
plot(residuals(temp_arima_final), type = "l",
     main = "Reszty modelu ARIMA dla temperatury",
     xlab = "Rok", ylab = "Reszty")
grid()
Acf(residuals(temp_arima_final), lag.max = 24,
    main = "ACF reszt modelu ARIMA",
    xlab = "Opóźnienie", ylab = "Autokorelacja")
temp_lb_pvalues <- rep(NA_real_, 24)
for (i in seq_along(temp_lb_pvalues)) {
  if (i > temp_arima_fitdf) {
    temp_lb_pvalues[i] <- Box.test(residuals(temp_arima_final), lag = i,
                                   type = "Ljung-Box", fitdf = temp_arima_fitdf)$p.value
  }
}
plot(temp_lb_pvalues, type = "h", ylim = c(0, 1),
     main = "Wartości p testu Ljunga-Boxa",
     xlab = "Opóźnienie", ylab = "Wartość p")
abline(h = 0.05, col = "red", lty = 2)
grid()
par(mfrow = c(1, 1))
invisible(dev.off())
message("Zapisano wykres: ", normalizePath(temp_arima_diag_path, winslash = "/", mustWork = FALSE))

temp_arima_acf_path <- file.path(fig_dir, "temp_arima_acf_pacf.pdf")
# Wyższy format poprawia widoczność słupków ACF i PACF reszt.
pdf(temp_arima_acf_path, width = 7, height = 7.5)
par(mfrow = c(2, 1))
Acf(resid(temp_arima_final), lag.max = 36, lwd = 7, col = "dark green",
    main = "ACF reszt modelu ARIMA",
    xlab = "Opóźnienie", ylab = "Autokorelacja")
Pacf(resid(temp_arima_final), lag.max = 36, lwd = 7, col = "dark green",
     main = "PACF reszt modelu ARIMA",
     xlab = "Opóźnienie", ylab = "Autokorelacja cząstkowa")
par(mfrow = c(1, 1))
invisible(dev.off())
message("Zapisano wykres: ", normalizePath(temp_arima_acf_path, winslash = "/", mustWork = FALSE))

# Miary błędów ex post.
temp_hw_err <- as.numeric(temp_test) - as.numeric(temp_hw_pred)
temp_arima_err <- as.numeric(temp_test) - as.numeric(temp_arima_pred)
temp_hw_me <- mean(temp_hw_err)
temp_hw_mae <- mean(abs(temp_hw_err))
temp_hw_rmse <- sqrt(mean(temp_hw_err^2))
temp_hw_mape <- mean(abs(temp_hw_err / as.numeric(temp_test))) * 100
temp_arima_me <- mean(temp_arima_err)
temp_arima_mae <- mean(abs(temp_arima_err))
temp_arima_rmse <- sqrt(mean(temp_arima_err^2))
temp_arima_mape <- mean(abs(temp_arima_err / as.numeric(temp_test))) * 100

# Kryteria informacyjne modelu Holta z pakietu forecast.
temp_hw_aic <- temp_holt_final$model$aic
temp_hw_bic <- temp_holt_final$model$bic

# Wykres prognoz out-of-sample temperatury: 2024--2025.
# Wykres prognoz out-of-sample temperatury: 2024--2025.
temp_forecast_path <- file.path(fig_dir, "temp_prognozy.pdf")

temp_os_end <- end(temp_test)[1]

temp_last_train_year <- end(temp_train)[1]
temp_last_train_value <- tail(as.numeric(temp_train), 1)

temp_hw_pred_ts <- ts(
  c(temp_last_train_value, as.numeric(temp_hw_pred)),
  start = temp_last_train_year,
  frequency = 1
)

temp_arima_pred_ts <- ts(
  c(temp_last_train_value, as.numeric(temp_arima_pred)),
  start = temp_last_train_year,
  frequency = 1
)
pdf(temp_forecast_path, width = 7, height = 4.2)

plot(window(temp_ts, start = 2015), type = "n",
     xlim = c(2015, temp_os_end),
     ylim = range(c(window(temp_ts, start = 2015),
                    temp_hw_pred_ts,
                    temp_arima_pred_ts), na.rm = TRUE),
     main = "Prognozy out-of-sample temperatury",
     xlab = "Rok", ylab = "Temperatura [st. C]")

# Najpierw prognozy, żeby były pod spodem
lines(temp_hw_pred_ts, col = "blue", lwd = 2)

lines(temp_arima_pred_ts, col = "red", lwd = 2)

# Na końcu wartości rzeczywiste, żeby były na wierzchu
lines(window(temp_ts, start = 2015), type = "l", col = "black")

legend("bottomright",
       legend = c("dane rzeczywiste", "Holt", "ARIMA(4,0,1)"),
       col = c("black", "blue", "red"),
       lty = c(1, 1, 1),
       bty = "n", cex = 0.8)

grid()
invisible(dev.off())

message("Zapisano wykres: ", normalizePath(temp_forecast_path, winslash = "/", mustWork = FALSE))
# Tabele dla szeregu niesezonowego.
temp_opis_path <- file.path(tab_dir, "temp_opis.tex")
writeLines(c(
  "\\begin{tabular}{lr}",
  "\\toprule",
  "\\textbf{Miara} & \\textbf{Wartość}",
  "\\\\",
  "\\midrule",
  paste("Liczba obserwacji &", length(temp_ts)),
  "\\\\",
  paste("Zakres &", paste0(start(temp_ts)[1], "--", end(temp_ts)[1])),
  "\\\\",
  paste("Minimum &", formatC(min(temp_ts), digits = 3, format = "f", decimal.mark = ",")),
  "\\\\",
  paste("Maksimum &", formatC(max(temp_ts), digits = 3, format = "f", decimal.mark = ",")),
  "\\\\",
  paste("Średnia &", formatC(mean(temp_ts), digits = 3, format = "f", decimal.mark = ",")),
  "\\\\",
  paste("Odchylenie standardowe &", formatC(sd(as.numeric(temp_ts)), digits = 3, format = "f", decimal.mark = ",")),
  "\\\\",
  "\\bottomrule",
  "\\end{tabular}"
), temp_opis_path, useBytes = TRUE)
message("Zapisano tabelę: ", normalizePath(temp_opis_path, winslash = "/", mustWork = FALSE))

temp_modele_path <- file.path(tab_dir, "temp_modele.tex")

writeLines(c(
  "\\begin{tabular}{lrrr}",
  "\\toprule",
  "\\textbf{Model} & \\textbf{MAE} & \\textbf{RMSE} & \\textbf{MAPE}",
  "\\\\",
  "\\midrule",
  paste("Holt &",
        formatC(temp_hw_mae, digits = 3, format = "f", decimal.mark = ","), "&",
        formatC(temp_hw_rmse, digits = 3, format = "f", decimal.mark = ","), "&",
        formatC(temp_hw_mape, digits = 3, format = "f", decimal.mark = ",")),
  "\\\\",
  paste(temp_arima_label, "&",
        formatC(temp_arima_mae, digits = 3, format = "f", decimal.mark = ","), "&",
        formatC(temp_arima_rmse, digits = 3, format = "f", decimal.mark = ","), "&",
        formatC(temp_arima_mape, digits = 3, format = "f", decimal.mark = ",")),
  "\\\\",
  "\\bottomrule",
  "\\end{tabular}"
), temp_modele_path, useBytes = TRUE)

message("Zapisano tabelę: ", normalizePath(temp_modele_path, winslash = "/", mustWork = FALSE))

# Tabela porównuje modele ekstrapolacyjne omawiane we wzorcach ASC.
temp_ekstrap_path <- file.path(tab_dir, "temp_ekstrapolacyjne_porownanie.tex")
temp_ekstrap_lines <- c(
  "\\begin{tabular}{lrrr}",
  "\\toprule",
  "\\textbf{Model} & \\textbf{Fit MAE} & \\textbf{Fit RMSE} & \\textbf{Fit MAPE}",
  "\\\\",
  "\\midrule"
)
for (i in seq_len(nrow(temp_extrap_compare))) {
  temp_ekstrap_lines <- c(
    temp_ekstrap_lines,
    paste(temp_extrap_compare$model[i], "&",
          formatC(temp_extrap_compare$Fit_MAE[i], digits = 3, format = "f", decimal.mark = ","), "&",
          formatC(temp_extrap_compare$Fit_RMSE[i], digits = 3, format = "f", decimal.mark = ","), "&",
          formatC(temp_extrap_compare$Fit_MAPE[i], digits = 3, format = "f", decimal.mark = ",")),
    "\\\\"
  )
}
temp_ekstrap_lines <- c(temp_ekstrap_lines, "\\bottomrule", "\\end{tabular}")
writeLines(temp_ekstrap_lines, temp_ekstrap_path, useBytes = TRUE)
message("Zapisano tabelę: ", normalizePath(temp_ekstrap_path, winslash = "/", mustWork = FALSE))

temp_prognozy_path <- file.path(tab_dir, "temp_prognozy.tex")

temp_prognozy_lines <- c(
  "\\begin{tabular}{lrrr}",
  "\\toprule",
  "\\textbf{Rok} & \\textbf{Wartość rzeczywista} & \\textbf{Holt} & \\textbf{ARIMA(4,0,1)}",
  "\\\\",
  "\\midrule"
)

temp_test_years <- as.integer(time(temp_test))

for (i in seq_along(temp_test)) {
  temp_prognozy_lines <- c(
    temp_prognozy_lines,
    paste(
      temp_test_years[i], "&",
      formatC(as.numeric(temp_test)[i], digits = 3, format = "f", decimal.mark = ","), "&",
      formatC(as.numeric(temp_hw_pred)[i], digits = 3, format = "f", decimal.mark = ","), "&",
      formatC(as.numeric(temp_arima_pred)[i], digits = 3, format = "f", decimal.mark = ",")
    ),
    "\\\\"
  )
}

temp_prognozy_lines <- c(
  temp_prognozy_lines,
  "\\bottomrule",
  "\\end{tabular}"
)

writeLines(temp_prognozy_lines, temp_prognozy_path, useBytes = TRUE)
message("Zapisano tabelę: ", normalizePath(temp_prognozy_path, winslash = "/", mustWork = FALSE))
# =============================================================================
# SZEREG SEZONOWY: GOOGLE TRENDS DLA FRAZY "KEVIN SAM W DOMU"
# =============================================================================

# Dane miesięczne Google Trends obcinamy do grudnia 2025.
kevin_raw <- read.csv(file.path(root_dir, "sezonowy", "kevin2004teraz.csv"),
                      fileEncoding = "UTF-8")
names(kevin_raw) <- c("date", "kevin")
kevin_raw$date <- as.Date(kevin_raw$date)
kevin_project <- subset(kevin_raw, date <= as.Date("2025-12-01"))
kevin_ts <- ts(kevin_project$kevin, start = c(2004, 1), frequency = 12)
# Dekompozycję liczymy przed wykresem, aby pokazać na nim również szereg odsezonowany.
kevin_decomp <- decompose(kevin_ts, type = "additive")
kevin_adjusted <- kevin_ts - kevin_decomp$seasonal
message("Wczytano szereg Kevin: ", length(kevin_ts), " obserwacje miesięczne.")

# Wykres szeregu czasowego.
kevin_szereg_path <- file.path(fig_dir, "kevin_szereg.pdf")
pdf(kevin_szereg_path, width = 7, height = 4.2)
plot(kevin_ts, type = "l", col = "black",
     main = "Popularność frazy \"Kevin sam w domu\" w Google Trends",
     xlab = "Rok", ylab = "Indeks Google Trends",
     ylim = range(c(kevin_ts, kevin_adjusted), na.rm = TRUE))
lines(kevin_adjusted, col = "red", lwd = 2)
legend("topleft", legend = c("szereg oryginalny", "szereg odsezonowany"),
       col = c("black", "red"), lty = c(1, 1),
       bty = "n", cex = 0.8)
grid()
invisible(dev.off())
message("Zapisano wykres: ", normalizePath(kevin_szereg_path, winslash = "/", mustWork = FALSE))

# Dekompozycja addytywna i wykres sezonowy.
kevin_decomp_path <- file.path(fig_dir, "kevin_dekompozycja.pdf")
pdf(kevin_decomp_path, width = 7, height = 6)
par(mfrow = c(4, 1), mar = c(3, 4, 2.2, 1))
plot(kevin_decomp$x, type = "l",
     main = "Szereg Google Trends",
     xlab = "Rok", ylab = "Indeks")
plot(kevin_decomp$trend, type = "l",
     main = "Trend",
     xlab = "Rok", ylab = "Trend")
plot(kevin_decomp$seasonal, type = "l",
     main = "Składnik sezonowy",
     xlab = "Rok", ylab = "Sezonowość")
plot(kevin_decomp$random, type = "l",
     main = "Składnik losowy",
     xlab = "Rok", ylab = "Reszty")
par(mfrow = c(1, 1), mar = c(5, 4, 4, 2) + 0.1)
invisible(dev.off())
message("Zapisano wykres: ", normalizePath(kevin_decomp_path, winslash = "/", mustWork = FALSE))

kevin_season_path <- file.path(fig_dir, "kevin_sezonowosc.pdf")
pdf(kevin_season_path, width = 7, height = 4.2)
monthplot(kevin_ts, main = "Sezonowość wyszukiwań frazy",
          xlab = "Miesiąc", ylab = "Indeks Google Trends")
grid()
invisible(dev.off())
message("Zapisano wykres: ", normalizePath(kevin_season_path, winslash = "/", mustWork = FALSE))

# Podział próby: model uczymy do 2024, testujemy na 2025 roku.
kevin_train <- window(kevin_ts, end = c(2024, 12))
kevin_test <- window(kevin_ts, start = c(2025, 1))

# Porównanie wariantu addytywnego i multiplikatywnego metody Holta-Wintersa.
kevin_hw_add_train <- hw(kevin_train, h = length(kevin_test), seasonal = "additive")
kevin_hw_add_final <- hw(kevin_ts, h = 12, seasonal = "additive")

# Wariant multiplikatywny wymaga dodatnich wartości szeregu.
if (all(kevin_train > 0) && all(kevin_ts > 0)) {
  kevin_hw_mult_train <- hw(kevin_train, h = length(kevin_test), seasonal = "multiplicative")
  kevin_hw_mult_final <- hw(kevin_ts, h = 12, seasonal = "multiplicative")
} else {
  kevin_hw_mult_train <- NULL
  kevin_hw_mult_final <- NULL
  message("Pominięto multiplikatywny Holt-Winters: szereg Kevin zawiera zera.")
}

kevin_hw_add_path <- file.path(fig_dir, "kevin_hw_addytywny.pdf")
pdf(kevin_hw_add_path, width = 7, height = 4.2)
plot(kevin_train, type = "l",
     main = "Prognoza addytywnego modelu Holta-Wintersa",
     xlab = "Rok", ylab = "Indeks Google Trends",
     xlim = c(2020, 2026),
     ylim = range(c(window(kevin_train, start = c(2020, 1)),
                    kevin_test, kevin_hw_add_train$mean), na.rm = TRUE))
lines(kevin_hw_add_train$mean, col = "blue", lwd = 2)
lines(kevin_test, col = "black", lwd = 1, lty = 2)
legend("topleft", legend = c("dane uczące", "dane testowe", "prognoza"),
       col = c("black", "black", "blue"), lty = c(1, 2, 1),
       bty = "n", cex = 0.8)
grid()
invisible(dev.off())
message("Zapisano wykres: ", normalizePath(kevin_hw_add_path, winslash = "/", mustWork = FALSE))

if (!is.null(kevin_hw_mult_train)) {
  kevin_hw_mult_path <- file.path(fig_dir, "kevin_hw_multiplikatywny.pdf")
  pdf(kevin_hw_mult_path, width = 7, height = 4.2)
  plot(kevin_train, type = "l",
       main = "Prognoza multiplikatywnego modelu Holta-Wintersa",
       xlab = "Rok", ylab = "Indeks Google Trends",
       xlim = c(2020, 2026),
       ylim = range(c(window(kevin_train, start = c(2020, 1)),
                      kevin_test, kevin_hw_mult_train$mean), na.rm = TRUE))
  lines(kevin_hw_mult_train$mean, col = "green", lwd = 2)
  lines(kevin_test, col = "black", lwd = 1, lty = 2)
  legend("topleft", legend = c("dane uczące", "dane testowe", "prognoza"),
         col = c("black", "black", "green"), lty = c(1, 2, 1),
         bty = "n", cex = 0.8)
  grid()
  invisible(dev.off())
  message("Zapisano wykres: ", normalizePath(kevin_hw_mult_path, winslash = "/", mustWork = FALSE))
}

kevin_hw_fit_path <- file.path(fig_dir, "kevin_hw_dopasowanie.pdf")
pdf(kevin_hw_fit_path, width = 7, height = 4.2)
plot(kevin_train, type = "l", col = "black",
     main = "Dopasowanie addytywnego modelu Holta-Wintersa",
     xlab = "Rok", ylab = "Indeks Google Trends",
     ylim = range(c(kevin_train, fitted(kevin_hw_add_train)), na.rm = TRUE))
lines(fitted(kevin_hw_add_train), col = "blue", lwd = 2)
legend("topleft", legend = c("wartości rzeczywiste", "wartości modelu"),
       col = c("black", "blue"), lty = c(1, 1),
       bty = "n", cex = 0.8)
grid()
invisible(dev.off())
message("Zapisano wykres: ", normalizePath(kevin_hw_fit_path, winslash = "/", mustWork = FALSE))

kevin_hw_add_train$model
if (!is.null(kevin_hw_mult_train)) {
  kevin_hw_mult_train$model
}

kryteria <- c("MAE", "RMSE", "MAPE", "MASE")
kevin_hw_add_accuracy <- accuracy(kevin_hw_add_train, kevin_test)[, kryteria]
if (!is.null(kevin_hw_mult_train)) {
  kevin_hw_mult_accuracy <- accuracy(kevin_hw_mult_train, kevin_test)[, kryteria]
} else {
  kevin_hw_mult_accuracy <- matrix(NA, nrow = 1, ncol = length(kryteria))
  colnames(kevin_hw_mult_accuracy) <- kryteria
  rownames(kevin_hw_mult_accuracy) <- "Test set"
}
kevin_hw_add_accuracy
kevin_hw_mult_accuracy

kevin_hw_train <- kevin_hw_add_train
kevin_hw_pred <- kevin_hw_add_train$mean
kevin_hw_final <- kevin_hw_add_final
kevin_hw_fc <- kevin_hw_add_final$mean

# Modele SARIMA estymowane jawnie, jak we wzorcach.
# Rozważamy modele bez różnicowania, z komponentami niesezonowymi i sezonowymi
# wskazanymi przez ACF/PACF; diagnostykę reszt porównujemy testem Ljunga-Boxa dla 24 opóźnień.
kevin_sarima_specs <- data.frame(
  model = c("SARIMA(0,0,0)(1,0,0)[12]",
            "SARIMA(0,0,0)(0,0,1)[12]",
            "SARIMA(0,0,0)(1,0,1)[12]",
            "SARIMA(1,0,0)(1,0,0)[12]",
            "SARIMA(0,0,1)(1,0,0)[12]",
            "SARIMA(1,0,1)(1,0,0)[12]",
            "SARIMA(0,0,1)(1,0,1)[12]",
            "SARIMA(1,0,1)(1,0,1)[12]"),
  p = c(0, 0, 0, 1, 0, 1, 0, 1),
  d = rep(0, 8),
  q = c(0, 0, 0, 0, 1, 1, 1, 1),
  P = c(1, 0, 1, 1, 1, 1, 1, 1),
  D = rep(0, 8),
  Q = c(0, 1, 1, 0, 0, 0, 1, 1)
)
kevin_sarima_train_models <- vector("list", nrow(kevin_sarima_specs))
kevin_sarima_ok <- rep(FALSE, nrow(kevin_sarima_specs))
for (i in seq_len(nrow(kevin_sarima_specs))) {
  # Modele estymujemy na próbie uczącej, aby porównanie AIC/BIC było spójne.
  kevin_fit <- try(arima(
    kevin_train,
    order = c(kevin_sarima_specs$p[i],
              kevin_sarima_specs$d[i],
              kevin_sarima_specs$q[i]),
    seasonal = list(order = c(kevin_sarima_specs$P[i],
                              kevin_sarima_specs$D[i],
                              kevin_sarima_specs$Q[i]),
                    period = 12),
    method = "ML"
  ), silent = TRUE)
  if (!inherits(kevin_fit, "try-error")) {
    kevin_sarima_train_models[[i]] <- kevin_fit
    kevin_sarima_ok[i] <- TRUE
  }
}
kevin_sarima_compare <- data.frame(
  model = kevin_sarima_specs$model[kevin_sarima_ok],
  p = kevin_sarima_specs$p[kevin_sarima_ok],
  d = kevin_sarima_specs$d[kevin_sarima_ok],
  q = kevin_sarima_specs$q[kevin_sarima_ok],
  P = kevin_sarima_specs$P[kevin_sarima_ok],
  D = kevin_sarima_specs$D[kevin_sarima_ok],
  Q = kevin_sarima_specs$Q[kevin_sarima_ok],
  AIC = sapply(kevin_sarima_train_models[kevin_sarima_ok], AIC),
  BIC = sapply(kevin_sarima_train_models[kevin_sarima_ok], BIC)
)
# Dla każdego kandydata sprawdzamy autokorelację reszt testem Ljunga-Boxa.
kevin_sarima_compare$LB_lag <- NA_integer_
kevin_sarima_compare$LB_stat <- NA_real_
kevin_sarima_compare$LB_p <- NA_real_
for (i in seq_len(nrow(kevin_sarima_compare))) {
  kevin_fit <- kevin_sarima_train_models[[which(kevin_sarima_specs$model ==
                                                  kevin_sarima_compare$model[i])]]
  kevin_fitdf <- length(kevin_fit$coef)
  kevin_lag <- 24
  kevin_lb_candidate <- Box.test(residuals(kevin_fit), lag = kevin_lag,
                                 type = "Ljung-Box", fitdf = kevin_fitdf)
  kevin_sarima_compare$LB_lag[i] <- kevin_lag
  kevin_sarima_compare$LB_stat[i] <- as.numeric(kevin_lb_candidate$statistic)
  kevin_sarima_compare$LB_p[i] <- kevin_lb_candidate$p.value
}
kevin_sarima_compare <- kevin_sarima_compare[order(kevin_sarima_compare$AIC), ]
rownames(kevin_sarima_compare) <- NULL
print(kevin_sarima_compare)

kevin_sarima_kandydaci_path <- file.path(tab_dir, "kevin_sarima_kandydaci.tex")
kevin_sarima_kandydaci_lines <- c(
  "\\begin{tabular}{lrrrrrr}",
  "\\toprule",
  "\\textbf{Model} & \\textbf{AIC} & \\textbf{BIC} & \\textbf{Lag LB} & \\textbf{Stat. LB} & \\textbf{LB p} \\\\",
  "\\midrule"
)
for (i in seq_len(nrow(kevin_sarima_compare))) {
  kevin_sarima_kandydaci_lines <- c(
    kevin_sarima_kandydaci_lines,
    paste(
      kevin_sarima_compare$model[i], "&",
      formatC(kevin_sarima_compare$AIC[i], digits = 3, format = "f", decimal.mark = ","), "&",
      formatC(kevin_sarima_compare$BIC[i], digits = 3, format = "f", decimal.mark = ","), "&",
      kevin_sarima_compare$LB_lag[i], "&",
      formatC(kevin_sarima_compare$LB_stat[i], digits = 3, format = "f", decimal.mark = ","), "&",
      formatC(kevin_sarima_compare$LB_p[i], digits = 3, format = "f", decimal.mark = ",")
    ),
    "\\\\"
  )
}
kevin_sarima_kandydaci_lines <- c(kevin_sarima_kandydaci_lines,
                                  "\\bottomrule", "\\end{tabular}")
writeLines(kevin_sarima_kandydaci_lines, kevin_sarima_kandydaci_path, useBytes = TRUE)
message("Zapisano tabelę: ", normalizePath(kevin_sarima_kandydaci_path, winslash = "/", mustWork = FALSE))

kevin_sarima_best <- kevin_sarima_compare[1, ]
kevin_sarima_label <- kevin_sarima_best$model
kevin_sarima_train_index <- which(kevin_sarima_specs$model == kevin_sarima_label)
kevin_sarima_train <- kevin_sarima_train_models[[kevin_sarima_train_index]]
kevin_sarima_pred <- predict(kevin_sarima_train, n.ahead = length(kevin_test))$pred

kevin_hw_err <- as.numeric(kevin_test) - as.numeric(kevin_hw_pred)
kevin_sarima_err <- as.numeric(kevin_test) - as.numeric(kevin_sarima_pred)

kevin_hw_mae <- mean(abs(kevin_hw_err))
kevin_hw_rmse <- sqrt(mean(kevin_hw_err^2))
kevin_hw_mape <- mean(abs(kevin_hw_err / as.numeric(kevin_test))) * 100

kevin_sarima_mae <- mean(abs(kevin_sarima_err))
kevin_sarima_rmse <- sqrt(mean(kevin_sarima_err^2))
kevin_sarima_mape <- mean(abs(kevin_sarima_err / as.numeric(kevin_test))) * 100

kevin_sarima_porownanie_path <- file.path(tab_dir, "kevin_sarima_porownanie.tex")

writeLines(c(
  "\\begin{tabular}{lrrr}",
  "\\toprule",
  "\\textbf{Model} & \\textbf{MAE} & \\textbf{RMSE} & \\textbf{MAPE}",
  "\\\\",
  "\\midrule",
  paste("Holt-Winters addytywny &",
        formatC(kevin_hw_mae, digits = 3, format = "f", decimal.mark = ","), "&",
        formatC(kevin_hw_rmse, digits = 3, format = "f", decimal.mark = ","), "&",
        formatC(kevin_hw_mape, digits = 3, format = "f", decimal.mark = ",")),
  "\\\\",
  paste(kevin_sarima_label, "&",
        formatC(kevin_sarima_mae, digits = 3, format = "f", decimal.mark = ","), "&",
        formatC(kevin_sarima_rmse, digits = 3, format = "f", decimal.mark = ","), "&",
        formatC(kevin_sarima_mape, digits = 3, format = "f", decimal.mark = ",")),
  "\\\\",
  "\\bottomrule",
  "\\end{tabular}"
), kevin_sarima_porownanie_path, useBytes = TRUE)

message("Zapisano tabelę: ", normalizePath(kevin_sarima_porownanie_path, winslash = "/", mustWork = FALSE))

kevin_sarima_final <- arima(
  kevin_ts,
  order = c(kevin_sarima_best$p, kevin_sarima_best$d, kevin_sarima_best$q),
  seasonal = list(order = c(kevin_sarima_best$P,
                            kevin_sarima_best$D,
                            kevin_sarima_best$Q),
                  period = 12),
  method = "ML"
)

# Tabela istotności parametrów najlepszego modelu SARIMA z próby uczącej.
kevin_sarima_best_coef <- coeftest(kevin_sarima_train)
kevin_sarima_parametry_path <- file.path(tab_dir, "kevin_sarima_parametry.tex")
kevin_sarima_parametry_lines <- c(
  "\\begin{tabular}{lrrrr}",
  "\\toprule",
  "\\textbf{Parametr} & \\textbf{Oszacowanie} & \\textbf{Błąd std.} & \\textbf{z} & \\textbf{p-value} \\\\",
  "\\midrule"
)
for (i in seq_len(nrow(kevin_sarima_best_coef))) {
  kevin_sarima_parametry_lines <- c(
    kevin_sarima_parametry_lines,
    paste(
      rownames(kevin_sarima_best_coef)[i], "&",
      formatC(kevin_sarima_best_coef[i, 1], digits = 3, format = "f", decimal.mark = ","), "&",
      formatC(kevin_sarima_best_coef[i, 2], digits = 3, format = "f", decimal.mark = ","), "&",
      formatC(kevin_sarima_best_coef[i, 3], digits = 3, format = "f", decimal.mark = ","), "&",
      formatC(kevin_sarima_best_coef[i, 4], digits = 3, format = "f", decimal.mark = ","),
      "\\\\"
    )
  )
}
kevin_sarima_parametry_lines <- c(
  kevin_sarima_parametry_lines,
  "\\bottomrule",
  "\\end{tabular}"
)
writeLines(kevin_sarima_parametry_lines, kevin_sarima_parametry_path, useBytes = TRUE)
message("Zapisano tabelę: ", normalizePath(kevin_sarima_parametry_path, winslash = "/", mustWork = FALSE))

kevin_sarima_pred <- predict(kevin_sarima_train, n.ahead = length(kevin_test))$pred
kevin_sarima_fc <- predict(kevin_sarima_final, n.ahead = 12)$pred

# Wartości modelu SARIMA wyznaczamy jako obserwacje pomniejszone o reszty modelu.
kevin_sarima_fitted <- ts(as.numeric(kevin_ts) - as.numeric(residuals(kevin_sarima_final)),
                          start = start(kevin_ts), frequency = frequency(kevin_ts))
kevin_sarima_fit_path <- file.path(fig_dir, "kevin_sarima_dopasowanie.pdf")
pdf(kevin_sarima_fit_path, width = 7, height = 4.2)
plot(kevin_ts, type = "l", col = "black",
     main = "Dopasowanie modelu SARIMA dla Google Trends",
     xlab = "Rok", ylab = "Indeks Google Trends",
     ylim = range(c(kevin_ts, kevin_sarima_fitted), na.rm = TRUE))
lines(kevin_sarima_fitted, col = "red", lwd = 2)
legend("topleft", legend = c("wartości rzeczywiste", "wartości modelu"),
       col = c("black", "red"), lty = c(1, 1),
       bty = "n", cex = 0.8)
grid()
invisible(dev.off())
message("Zapisano wykres: ", normalizePath(kevin_sarima_fit_path, winslash = "/", mustWork = FALSE))

# Test ADF dla poziomu i różnicy sezonowej.
kevin_adf_max_lag <- 12
kevin_adf_level_results <- data.frame(lag = 0:kevin_adf_max_lag,
                                      stat = NA_real_,
                                      crit5 = NA_real_,
                                      bg_p = NA_real_,
                                      wniosek = NA_character_)
kevin_adf_level_models <- vector("list", nrow(kevin_adf_level_results))
for (i in seq_len(nrow(kevin_adf_level_results))) {
  # Kontrolujemy, czy reszty równania DF/ADF nie są autokorelowane.
  kevin_fit <- ur.df(kevin_ts, type = c("drift"),
                     lags = kevin_adf_level_results$lag[i])
  kevin_adf_level_models[[i]] <- kevin_fit
  kevin_adf_level_results$stat[i] <- kevin_fit@teststat[1]
  kevin_adf_level_results$crit5[i] <- kevin_fit@cval[1, "5pct"]
  kevin_adf_level_results$bg_p[i] <- bgtest(kevin_fit@testreg$residuals ~ 1,
                                            order = 1)$p.value
  kevin_adf_level_results$wniosek[i] <- ifelse(kevin_adf_level_results$stat[i] <
                                                 kevin_adf_level_results$crit5[i],
                                               "stacjonarny", "niestacjonarny")
}
kevin_adf_level_choice <- which(kevin_adf_level_results$bg_p >= 0.05)[1]
if (is.na(kevin_adf_level_choice)) {
  kevin_adf_level_choice <- nrow(kevin_adf_level_results)
}
kevin_adf_level <- kevin_adf_level_models[[kevin_adf_level_choice]]
kevin_adf_level_lag <- kevin_adf_level_results$lag[kevin_adf_level_choice]
kevin_adf_level_stat <- kevin_adf_level_results$stat[kevin_adf_level_choice]
kevin_adf_level_crit <- kevin_adf_level_results$crit5[kevin_adf_level_choice]
kevin_adf_level_bg_p <- kevin_adf_level_results$bg_p[kevin_adf_level_choice]
kevin_adf_level_wniosek <- kevin_adf_level_results$wniosek[kevin_adf_level_choice]

kevin_seasdiff <- diff(kevin_ts, lag = 12)
kevin_adf_seasdiff_results <- data.frame(lag = 0:kevin_adf_max_lag,
                                         stat = NA_real_,
                                         crit5 = NA_real_,
                                         bg_p = NA_real_,
                                         wniosek = NA_character_)
kevin_adf_seasdiff_models <- vector("list", nrow(kevin_adf_seasdiff_results))
for (i in seq_len(nrow(kevin_adf_seasdiff_results))) {
  # Kontrolujemy reszty testu po różnicowaniu sezonowym.
  kevin_fit <- ur.df(kevin_seasdiff, type = c("drift"),
                     lags = kevin_adf_seasdiff_results$lag[i])
  kevin_adf_seasdiff_models[[i]] <- kevin_fit
  kevin_adf_seasdiff_results$stat[i] <- kevin_fit@teststat[1]
  kevin_adf_seasdiff_results$crit5[i] <- kevin_fit@cval[1, "5pct"]
  kevin_adf_seasdiff_results$bg_p[i] <- bgtest(kevin_fit@testreg$residuals ~ 1,
                                               order = 1)$p.value
  kevin_adf_seasdiff_results$wniosek[i] <- ifelse(kevin_adf_seasdiff_results$stat[i] <
                                                    kevin_adf_seasdiff_results$crit5[i],
                                                  "stacjonarny", "niestacjonarny")
}
kevin_adf_seasdiff_choice <- which(kevin_adf_seasdiff_results$bg_p >= 0.05)[1]
if (is.na(kevin_adf_seasdiff_choice)) {
  kevin_adf_seasdiff_choice <- nrow(kevin_adf_seasdiff_results)
}
kevin_adf_seasdiff <- kevin_adf_seasdiff_models[[kevin_adf_seasdiff_choice]]
kevin_adf_seasdiff_lag <- kevin_adf_seasdiff_results$lag[kevin_adf_seasdiff_choice]
kevin_adf_seasdiff_stat <- kevin_adf_seasdiff_results$stat[kevin_adf_seasdiff_choice]
kevin_adf_seasdiff_crit <- kevin_adf_seasdiff_results$crit5[kevin_adf_seasdiff_choice]
kevin_adf_seasdiff_bg_p <- kevin_adf_seasdiff_results$bg_p[kevin_adf_seasdiff_choice]
kevin_adf_seasdiff_wniosek <- kevin_adf_seasdiff_results$wniosek[kevin_adf_seasdiff_choice]

# Test sezonowości w szeregu po różnicowaniu sezonowym i zwykłym.
# Sprawdzamy, czy w stacjonarnej transformacji pozostają istotne efekty miesięcy.
kevin_stationary <- diff(kevin_seasdiff, differences = 1)
kevin_adf_stationary_results <- data.frame(lag = 0:kevin_adf_max_lag,
                                           stat = NA_real_,
                                           crit5 = NA_real_,
                                           bg_p = NA_real_,
                                           wniosek = NA_character_)
kevin_adf_stationary_models <- vector("list", nrow(kevin_adf_stationary_results))
for (i in seq_len(nrow(kevin_adf_stationary_results))) {
  # Kontrolujemy reszty testu po różnicowaniu sezonowym i zwykłym.
  kevin_fit <- ur.df(kevin_stationary, type = c("drift"),
                     lags = kevin_adf_stationary_results$lag[i])
  kevin_adf_stationary_models[[i]] <- kevin_fit
  kevin_adf_stationary_results$stat[i] <- kevin_fit@teststat[1]
  kevin_adf_stationary_results$crit5[i] <- kevin_fit@cval[1, "5pct"]
  kevin_adf_stationary_results$bg_p[i] <- bgtest(kevin_fit@testreg$residuals ~ 1,
                                                 order = 1)$p.value
  kevin_adf_stationary_results$wniosek[i] <- ifelse(kevin_adf_stationary_results$stat[i] <
                                                      kevin_adf_stationary_results$crit5[i],
                                                    "stacjonarny", "niestacjonarny")
}
kevin_adf_stationary_choice <- which(kevin_adf_stationary_results$bg_p >= 0.05)[1]
if (is.na(kevin_adf_stationary_choice)) {
  kevin_adf_stationary_choice <- nrow(kevin_adf_stationary_results)
}
kevin_adf_stationary <- kevin_adf_stationary_models[[kevin_adf_stationary_choice]]
kevin_adf_stationary_lag <- kevin_adf_stationary_results$lag[kevin_adf_stationary_choice]
kevin_adf_stationary_stat <- kevin_adf_stationary_results$stat[kevin_adf_stationary_choice]
kevin_adf_stationary_crit <- kevin_adf_stationary_results$crit5[kevin_adf_stationary_choice]
kevin_adf_stationary_bg_p <- kevin_adf_stationary_results$bg_p[kevin_adf_stationary_choice]
kevin_adf_stationary_wniosek <- kevin_adf_stationary_results$wniosek[kevin_adf_stationary_choice]
kevin_stationary_month <- factor(cycle(kevin_stationary), levels = 1:12,
                                 labels = month.abb)
kevin_season_lm <- lm(as.numeric(kevin_stationary) ~ kevin_stationary_month)
kevin_season_anova <- anova(kevin_season_lm)
kevin_season_anova_stat <- kevin_season_anova$`F value`[1]
kevin_season_anova_p <- kevin_season_anova$`Pr(>F)`[1]
kevin_season_kw <- kruskal.test(as.numeric(kevin_stationary) ~ kevin_stationary_month)
kevin_season_wniosek <- ifelse(kevin_season_anova_p < 0.05,
                               "istotna", "nieistotna")

kevin_season_stationary_path <- file.path(fig_dir, "kevin_sezonowosc_stacjonarny.pdf")
pdf(kevin_season_stationary_path, width = 7, height = 4.2)
boxplot(as.numeric(kevin_stationary) ~ kevin_stationary_month,
        main = "Sezonowość po różnicowaniu szeregu Google Trends",
        xlab = "Miesiąc", ylab = "Różnice sezonowe i zwykłe",
        col = "grey85", border = "grey35")
abline(h = 0, col = "red", lty = 2)
grid()
invisible(dev.off())
message("Zapisano wykres: ", normalizePath(kevin_season_stationary_path, winslash = "/", mustWork = FALSE))

# Korelogramy do wyboru rzędów p, q oraz sezonowych P i Q modelu SARIMA.
kevin_sarima_ident <- kevin_ts
kevin_sarima_ident_path <- file.path(fig_dir, "kevin_sarima_identyfikacja_acf_pacf.pdf")
pdf(kevin_sarima_ident_path, width = 7, height = 7.5)
par(mfrow = c(2, 1))
kevin_acf_ident <- acf(kevin_sarima_ident, lag.max = 36, plot = FALSE, na.action = na.pass)
kevin_acf_lags <- as.numeric(kevin_acf_ident$lag[-1]) * frequency(kevin_ts)
kevin_acf_values <- as.numeric(kevin_acf_ident$acf[-1])
kevin_acf_ci <- qnorm(0.975) / sqrt(length(kevin_sarima_ident))
kevin_acf_ylim <- range(c(kevin_acf_values, -kevin_acf_ci, kevin_acf_ci), na.rm = TRUE)
plot(kevin_acf_lags, kevin_acf_values, type = "n",
     main = "ACF szeregu Google Trends",
     xlab = "Opóźnienie", ylab = "Autokorelacja",
     ylim = kevin_acf_ylim, xlim = range(kevin_acf_lags))
rect(min(kevin_acf_lags) - 0.5, -kevin_acf_ci, max(kevin_acf_lags) + 0.5, kevin_acf_ci,
     col = "grey75", border = NA)
grid(col = "grey90")
abline(h = 0, col = "black")
segments(kevin_acf_lags, 0, kevin_acf_lags, kevin_acf_values, col = "#174A73", lwd = 1.4)
points(kevin_acf_lags, kevin_acf_values, pch = 16, col = "#174A73", cex = 0.9)
mtext("Szary pas: 95% granice istotności", side = 1, line = 3, adj = 0, cex = 0.75)

kevin_pacf_ident <- pacf(kevin_sarima_ident, lag.max = 36, plot = FALSE, na.action = na.pass)
kevin_pacf_lags <- as.numeric(kevin_pacf_ident$lag) * frequency(kevin_ts)
kevin_pacf_values <- as.numeric(kevin_pacf_ident$acf)
kevin_pacf_ci <- qnorm(0.975) / sqrt(length(kevin_sarima_ident))
kevin_pacf_ylim <- range(c(kevin_pacf_values, -kevin_pacf_ci, kevin_pacf_ci), na.rm = TRUE)
plot(kevin_pacf_lags, kevin_pacf_values, type = "n",
     main = "PACF szeregu Google Trends",
     xlab = "Opóźnienie", ylab = "Autokorelacja cząstkowa",
     ylim = kevin_pacf_ylim, xlim = range(kevin_pacf_lags))
rect(min(kevin_pacf_lags) - 0.5, -kevin_pacf_ci, max(kevin_pacf_lags) + 0.5, kevin_pacf_ci,
     col = "grey75", border = NA)
grid(col = "grey90")
abline(h = 0, col = "black")
segments(kevin_pacf_lags, 0, kevin_pacf_lags, kevin_pacf_values, col = "#174A73", lwd = 1.4)
points(kevin_pacf_lags, kevin_pacf_values, pch = 16, col = "#174A73", cex = 0.9)
mtext("Szary pas: 95% granice istotności", side = 1, line = 3, adj = 0, cex = 0.75)
par(mfrow = c(1, 1))
invisible(dev.off())
message("Zapisano wykres: ", normalizePath(kevin_sarima_ident_path, winslash = "/", mustWork = FALSE))

# Diagnostyka reszt SARIMA.
kevin_sarima_fitdf <- length(kevin_sarima_final$coef)
kevin_lb <- Box.test(residuals(kevin_sarima_final), lag = 24,
                     type = "Ljung-Box", fitdf = kevin_sarima_fitdf)
kevin_jb <- jarque.bera.test(residuals(kevin_sarima_final))

kevin_sarima_diag_path <- file.path(fig_dir, "kevin_sarima_diagnostyka.pdf")
pdf(kevin_sarima_diag_path, width = 7, height = 6)
par(mfrow = c(3, 1))
plot(residuals(kevin_sarima_final), type = "l",
     main = "Reszty modelu SARIMA dla Google Trends",
     xlab = "Rok", ylab = "Reszty")
grid()
Acf(residuals(kevin_sarima_final), lag.max = 24,
    main = "ACF reszt modelu SARIMA",
    xlab = "Opóźnienie", ylab = "Autokorelacja")
kevin_lb_pvalues <- rep(NA_real_, 24)
for (i in seq_along(kevin_lb_pvalues)) {
  if (i > kevin_sarima_fitdf) {
    kevin_lb_pvalues[i] <- Box.test(residuals(kevin_sarima_final), lag = i,
                                    type = "Ljung-Box", fitdf = kevin_sarima_fitdf)$p.value
  }
}
plot(kevin_lb_pvalues, type = "h", ylim = c(0, 1),
     main = "Wartości p testu Ljunga-Boxa",
     xlab = "Opóźnienie", ylab = "Wartość p")
abline(h = 0.05, col = "red", lty = 2)
grid()
par(mfrow = c(1, 1))
invisible(dev.off())
message("Zapisano wykres: ", normalizePath(kevin_sarima_diag_path, winslash = "/", mustWork = FALSE))

kevin_sarima_acf_path <- file.path(fig_dir, "kevin_sarima_acf_pacf.pdf")
pdf(kevin_sarima_acf_path, width = 7, height = 7.5)
par(mfrow = c(2, 1))
Acf(resid(kevin_sarima_final), lag.max = 36, lwd = 7, col = "dark green",
    main = "ACF reszt modelu SARIMA",
    xlab = "Opóźnienie", ylab = "Autokorelacja")
Pacf(resid(kevin_sarima_final), lag.max = 36, lwd = 7, col = "dark green",
     main = "PACF reszt modelu SARIMA",
     xlab = "Opóźnienie", ylab = "Autokorelacja cząstkowa")
par(mfrow = c(1, 1))
invisible(dev.off())
message("Zapisano wykres: ", normalizePath(kevin_sarima_acf_path, winslash = "/", mustWork = FALSE))

# Miary błędów ex post.
kevin_hw_err <- as.numeric(kevin_test) - as.numeric(kevin_hw_pred)
kevin_sarima_err <- as.numeric(kevin_test) - as.numeric(kevin_sarima_pred)
kevin_hw_me <- mean(kevin_hw_err)
kevin_hw_mae <- mean(abs(kevin_hw_err))
kevin_hw_rmse <- sqrt(mean(kevin_hw_err^2))
kevin_hw_mape <- mean(abs(kevin_hw_err / as.numeric(kevin_test))) * 100
if (!is.null(kevin_hw_mult_train)) {
  kevin_hw_mult_pred <- kevin_hw_mult_train$mean
  kevin_hw_mult_err <- as.numeric(kevin_test) - as.numeric(kevin_hw_mult_pred)
  kevin_hw_mult_mae <- mean(abs(kevin_hw_mult_err))
  kevin_hw_mult_rmse <- sqrt(mean(kevin_hw_mult_err^2))
  kevin_hw_mult_mape <- mean(abs(kevin_hw_mult_err / as.numeric(kevin_test))) * 100
} else {
  kevin_hw_mult_mae <- NA
  kevin_hw_mult_rmse <- NA
  kevin_hw_mult_mape <- NA
}
kevin_sarima_me <- mean(kevin_sarima_err)
kevin_sarima_mae <- mean(abs(kevin_sarima_err))
kevin_sarima_rmse <- sqrt(mean(kevin_sarima_err^2))
kevin_sarima_mape <- mean(abs(kevin_sarima_err / as.numeric(kevin_test))) * 100

# Kryteria informacyjne modelu hw() z pakietu forecast.
kevin_hw_aic <- kevin_hw_final$model$aic
kevin_hw_bic <- kevin_hw_final$model$bic
if (!is.null(kevin_hw_mult_final)) {
  kevin_hw_mult_aic <- kevin_hw_mult_final$model$aic
  kevin_hw_mult_bic <- kevin_hw_mult_final$model$bic
} else {
  kevin_hw_mult_aic <- NA
  kevin_hw_mult_bic <- NA
}

# Wykres prognoz szeregu sezonowego.
kevin_forecast_path <- file.path(fig_dir, "kevin_prognozy.pdf")
pdf(kevin_forecast_path, width = 7, height = 4.2)
kevin_last_train_value <- tail(as.numeric(kevin_train), 1)
kevin_hw_pred_plot <- ts(
  c(kevin_last_train_value, as.numeric(kevin_hw_pred)),
  start = c(2024, 12), frequency = 12
)
kevin_sarima_pred_plot <- ts(
  c(kevin_last_train_value, as.numeric(kevin_sarima_pred)),
  start = c(2024, 12), frequency = 12
)
plot(window(kevin_ts, start = c(2020, 1)), type = "l", col = "black",
     xlim = c(2020, 2026),
     ylim = range(c(window(kevin_ts, start = c(2020, 1)),
                    kevin_hw_pred_plot,
                    kevin_sarima_pred_plot), na.rm = TRUE),
     main = "Prognozy out-of-sample wyszukiwań frazy",
     xlab = "Rok", ylab = "Indeks Google Trends")
lines(kevin_hw_pred_plot, col = "blue", lwd = 2)
lines(kevin_sarima_pred_plot, col = "red", lwd = 2)
legend("topleft", legend = c("dane rzeczywiste", "Holt-Winters", "SARIMA"),
       col = c("black", "blue", "red"), lty = c(1, 1, 1),
       bty = "n", cex = 0.8)
grid()
invisible(dev.off())
message("Zapisano wykres: ", normalizePath(kevin_forecast_path, winslash = "/", mustWork = FALSE))

# Tabele dla szeregu sezonowego.
kevin_opis_path <- file.path(tab_dir, "kevin_opis.tex")
writeLines(c(
  "\\begin{tabular}{lr}",
  "\\toprule",
  "\\textbf{Miara} & \\textbf{Wartość}",
  "\\\\",
  "\\midrule",
  paste("Liczba obserwacji &", length(kevin_ts)),
  "\\\\",
  "Zakres & 2004-01--2025-12",
  "\\\\",
  paste("Minimum &", formatC(min(kevin_ts), digits = 3, format = "f", decimal.mark = ",")),
  "\\\\",
  paste("Maksimum &", formatC(max(kevin_ts), digits = 3, format = "f", decimal.mark = ",")),
  "\\\\",
  paste("Średnia &", formatC(mean(kevin_ts), digits = 3, format = "f", decimal.mark = ",")),
  "\\\\",
  paste("Odchylenie standardowe &", formatC(sd(as.numeric(kevin_ts)), digits = 3, format = "f", decimal.mark = ",")),
  "\\\\",
  "\\bottomrule",
  "\\end{tabular}"
), kevin_opis_path, useBytes = TRUE)
message("Zapisano tabelę: ", normalizePath(kevin_opis_path, winslash = "/", mustWork = FALSE))

kevin_modele_path <- file.path(tab_dir, "kevin_modele.tex")
writeLines(c(
  "\\begin{tabular}{lrrrrrr}",
  "\\toprule",
  "\\textbf{Model} & \\textbf{AIC} & \\textbf{BIC} & \\textbf{Ljung-Box p} & \\textbf{MAE} & \\textbf{RMSE} & \\textbf{MAPE}",
  "\\\\",
  "\\midrule",
  paste("Holt-Winters addytywny &",
        formatC(kevin_hw_aic, digits = 3, format = "f", decimal.mark = ","), "&",
        formatC(kevin_hw_bic, digits = 3, format = "f", decimal.mark = ","), "& -- &",
        formatC(kevin_hw_mae, digits = 3, format = "f", decimal.mark = ","), "&",
        formatC(kevin_hw_rmse, digits = 3, format = "f", decimal.mark = ","), "&",
        formatC(kevin_hw_mape, digits = 3, format = "f", decimal.mark = ",")),
  "\\\\",
  paste(kevin_sarima_label, "&",
        formatC(AIC(kevin_sarima_final), digits = 3, format = "f", decimal.mark = ","), "&",
        formatC(BIC(kevin_sarima_final), digits = 3, format = "f", decimal.mark = ","), "&",
        formatC(kevin_lb$p.value, digits = 3, format = "f", decimal.mark = ","), "&",
        formatC(kevin_sarima_mae, digits = 3, format = "f", decimal.mark = ","), "&",
        formatC(kevin_sarima_rmse, digits = 3, format = "f", decimal.mark = ","), "&",
        formatC(kevin_sarima_mape, digits = 3, format = "f", decimal.mark = ",")),
  "\\\\",
  "\\bottomrule",
  "\\end{tabular}"
), kevin_modele_path, useBytes = TRUE)
message("Zapisano tabelę: ", normalizePath(kevin_modele_path, winslash = "/", mustWork = FALSE))

kevin_prognozy_path <- file.path(tab_dir, "kevin_prognozy.tex")
kevin_prognozy_lines <- c(
  "\\begin{tabular}{lrrr}",
  "\\toprule",
  "\\textbf{Miesiąc} & \\textbf{Wartość rzeczywista} & \\textbf{Holt-Winters} & \\textbf{SARIMA}",
  "\\\\",
  "\\midrule"
)
for (i in seq_along(kevin_test)) {
  kevin_prognozy_lines <- c(
    kevin_prognozy_lines,
    paste(sprintf("2025-%02d", i), "&",
          formatC(as.numeric(kevin_test)[i], digits = 3, format = "f", decimal.mark = ","), "&",
          formatC(as.numeric(kevin_hw_pred)[i], digits = 3, format = "f", decimal.mark = ","), "&",
          formatC(as.numeric(kevin_sarima_pred)[i], digits = 3, format = "f", decimal.mark = ",")),
    "\\\\"
  )
}
kevin_prognozy_lines <- c(kevin_prognozy_lines, "\\bottomrule", "\\end{tabular}")
writeLines(kevin_prognozy_lines, kevin_prognozy_path, useBytes = TRUE)
message("Zapisano tabelę: ", normalizePath(kevin_prognozy_path, winslash = "/", mustWork = FALSE))

# Tabela testów stacjonarności dla szeregu temperatury.
temp_testy_path <- file.path(tab_dir, "temp_testy_stacjonarnosci.tex")
writeLines(c(
  "\\begin{tabular}{llrrrrr}",
  "\\toprule",
  "\\textbf{Szereg} & \\textbf{Wariant} & \\textbf{Lag} & \\textbf{Statystyka ADF} & \\textbf{Wartość kryt. 5 proc.} & \\textbf{BG p} & \\textbf{Wniosek}",
  "\\\\",
  "\\midrule",
  paste("Temperatura & poziom &", temp_adf_level_lag, "&",
        formatC(temp_adf_level_stat, digits = 3, format = "f", decimal.mark = ","), "&",
        formatC(temp_adf_level_crit, digits = 3, format = "f", decimal.mark = ","), "&",
        formatC(temp_adf_level_bg_p, digits = 3, format = "f", decimal.mark = ","), "&",
        temp_adf_level_wniosek),
  "\\\\",
  "\\bottomrule",
  "\\end{tabular}"
), temp_testy_path, useBytes = TRUE)
message("Zapisano tabelę: ", normalizePath(temp_testy_path, winslash = "/", mustWork = FALSE))

# Tabela testów stacjonarności dla szeregu Google Trends.
kevin_testy_path <- file.path(tab_dir, "kevin_testy_stacjonarnosci.tex")
writeLines(c(
  "\\begin{tabular}{llrrrrr}",
  "\\toprule",
  "\\textbf{Szereg} & \\textbf{Wariant} & \\textbf{Lag} & \\textbf{Statystyka ADF} & \\textbf{Wartość kryt. 5 proc.} & \\textbf{BG p} & \\textbf{Wniosek}",
  "\\\\",
  "\\midrule",
  paste("Kevin & poziom &", kevin_adf_level_lag, "&",
        formatC(kevin_adf_level_stat, digits = 3, format = "f", decimal.mark = ","), "&",
        formatC(kevin_adf_level_crit, digits = 3, format = "f", decimal.mark = ","), "&",
        formatC(kevin_adf_level_bg_p, digits = 3, format = "f", decimal.mark = ","), "&",
        kevin_adf_level_wniosek),
  "\\\\",
  paste("Kevin & różnica sezonowa &", kevin_adf_seasdiff_lag, "&",
        formatC(kevin_adf_seasdiff_stat, digits = 3, format = "f", decimal.mark = ","), "&",
        formatC(kevin_adf_seasdiff_crit, digits = 3, format = "f", decimal.mark = ","), "&",
        formatC(kevin_adf_seasdiff_bg_p, digits = 3, format = "f", decimal.mark = ","), "&",
        kevin_adf_seasdiff_wniosek),
  "\\\\",
  paste("Kevin & różnica sezonowa i zwykła &", kevin_adf_stationary_lag, "&",
        formatC(kevin_adf_stationary_stat, digits = 3, format = "f", decimal.mark = ","), "&",
        formatC(kevin_adf_stationary_crit, digits = 3, format = "f", decimal.mark = ","), "&",
        formatC(kevin_adf_stationary_bg_p, digits = 3, format = "f", decimal.mark = ","), "&",
        kevin_adf_stationary_wniosek),
  "\\\\",
  "\\bottomrule",
  "\\end{tabular}"
), kevin_testy_path, useBytes = TRUE)
message("Zapisano tabelę: ", normalizePath(kevin_testy_path, winslash = "/", mustWork = FALSE))

# Tabela testów sezonowości w stacjonarnej transformacji szeregu Google Trends.
kevin_sezonowosc_testy_path <- file.path(tab_dir, "kevin_sezonowosc_stacjonarny.tex")
writeLines(c(
  "\\begin{tabular}{lrrl}",
  "\\toprule",
  "\\textbf{Test} & \\textbf{Statystyka} & \\textbf{Wartość p} & \\textbf{Wniosek}",
  "\\\\",
  "\\midrule",
  paste("ANOVA efektów miesięcy &",
        formatC(kevin_season_anova_stat, digits = 3, format = "f", decimal.mark = ","), "&",
        formatC(kevin_season_anova_p, digits = 3, format = "f", decimal.mark = ","), "&",
        kevin_season_wniosek),
  "\\\\",
  paste("Kruskal-Wallis &",
        formatC(as.numeric(kevin_season_kw$statistic), digits = 3, format = "f", decimal.mark = ","), "&",
        formatC(kevin_season_kw$p.value, digits = 3, format = "f", decimal.mark = ","), "&",
        ifelse(kevin_season_kw$p.value < 0.05, "istotna", "nieistotna")),
  "\\\\",
  "\\bottomrule",
  "\\end{tabular}"
), kevin_sezonowosc_testy_path, useBytes = TRUE)
message("Zapisano tabelę: ", normalizePath(kevin_sezonowosc_testy_path, winslash = "/", mustWork = FALSE))

# Krótkie podsumowanie liczbowe.
summary_path <- file.path(out_dir, "podsumowanie.txt")
sink(summary_path)
cat("Temperatura: n =", length(temp_ts), "zakres =", start(temp_ts)[1], "-", end(temp_ts)[1], "\n")
cat("Wybrany model ARIMA:", temp_arima_label, "\n")
cat("Ljung-Box ARIMA p:", temp_lb$p.value, "\n")
cat("Jarque-Bera ARIMA p:", temp_jb$p.value, "\n")
cat("ADF temperatura poziom: lag =", temp_adf_level_lag,
    "stat =", temp_adf_level_stat,
    "kryt. 5% =", temp_adf_level_crit,
    "BG p =", temp_adf_level_bg_p,
    "wniosek:", temp_adf_level_wniosek, "\n")
cat("Holt: ME =", temp_hw_me, "MAE =", temp_hw_mae,
    "RMSE =", temp_hw_rmse, "MAPE =", temp_hw_mape, "\n")
cat("ARIMA: ME =", temp_arima_me, "MAE =", temp_arima_mae,
    "RMSE =", temp_arima_rmse, "MAPE =", temp_arima_mape, "\n")
cat("Modele ekstrapolacyjne temperatury - ranking wedlug RMSE out-of-sample:\n")
print(temp_extrap_compare)
cat("Najmniejszy blad prognozy ex post:", temp_extrap_best_error, "\n")
cat("Najlepsze dopasowanie in-sample wedlug Fit RMSE:", temp_extrap_best_fit, "\n")
cat("\nKevin: n =", length(kevin_ts), "zakres = 2004-01 - 2025-12\n")
cat("Wybrany model SARIMA:", kevin_sarima_label, "\n")
cat("Ljung-Box SARIMA p:", kevin_lb$p.value, "\n")
cat("Jarque-Bera SARIMA p:", kevin_jb$p.value, "\n")
cat("ADF Kevin poziom: lag =", kevin_adf_level_lag,
    "stat =", kevin_adf_level_stat,
    "kryt. 5% =", kevin_adf_level_crit,
    "BG p =", kevin_adf_level_bg_p,
    "wniosek:", kevin_adf_level_wniosek, "\n")
cat("ADF Kevin różnica sezonowa: lag =", kevin_adf_seasdiff_lag,
    "stat =", kevin_adf_seasdiff_stat,
    "kryt. 5% =", kevin_adf_seasdiff_crit,
    "BG p =", kevin_adf_seasdiff_bg_p,
    "wniosek:", kevin_adf_seasdiff_wniosek, "\n")
cat("ADF po różnicy sezonowej i zwykłej: lag =", kevin_adf_stationary_lag,
    "stat =", kevin_adf_stationary_stat,
    "kryt. 5% =", kevin_adf_stationary_crit,
    "BG p =", kevin_adf_stationary_bg_p,
    "wniosek:", kevin_adf_stationary_wniosek, "\n")
cat("Sezonowość w stacjonarnej transformacji ANOVA p:", kevin_season_anova_p,
    "wniosek:", kevin_season_wniosek, "\n")
cat("Sezonowość w stacjonarnej transformacji Kruskal-Wallis p:",
    kevin_season_kw$p.value, "\n")
cat("Holt-Winters addytywny: ME =", kevin_hw_me, "MAE =", kevin_hw_mae,
    "RMSE =", kevin_hw_rmse, "MAPE =", kevin_hw_mape, "\n")
if (!is.null(kevin_hw_mult_train)) {
  cat("Holt-Winters multiplikatywny: MAE =", kevin_hw_mult_mae,
      "RMSE =", kevin_hw_mult_rmse, "MAPE =", kevin_hw_mult_mape, "\n")
} else {
  cat("Holt-Winters multiplikatywny: niedostępny, bo szereg zawiera zera\n")
}
cat("SARIMA: ME =", kevin_sarima_me, "MAE =", kevin_sarima_mae,
    "RMSE =", kevin_sarima_rmse, "MAPE =", kevin_sarima_mape, "\n")
cat("\nPrognozy temperatury ARIMA:\n")
print(temp_arima_fc)
cat("\nPrognozy Kevin SARIMA:\n")
print(kevin_sarima_fc)
sink()
message("Zapisano podsumowanie: ", normalizePath(summary_path, winslash = "/", mustWork = FALSE))

message("")
message("Najważniejsze wyniki analizy:")
message("- Temperatura: ", temp_arima_label, ", Ljung-Box p = ",
        formatC(temp_lb$p.value, digits = 3, format = "f", decimal.mark = ","))
message("- Temperatura, modele ekstrapolacyjne: najmniejszy błąd ex post = ",
        temp_extrap_best_error, ", najlepsze dopasowanie = ", temp_extrap_best_fit)
message("- Temperatura w poziomie: ADF = ",
        formatC(temp_adf_level_stat, digits = 3, format = "f", decimal.mark = ","),
        ", BG p = ",
        formatC(temp_adf_level_bg_p, digits = 3, format = "f", decimal.mark = ","),
        " (", temp_adf_level_wniosek, ")")
message("- Kevin: ", kevin_sarima_label, ", Ljung-Box p = ",
        formatC(kevin_lb$p.value, digits = 3, format = "f", decimal.mark = ","))
message("- Sezonowość po różnicowaniu: ANOVA p = ",
        formatC(kevin_season_anova_p, digits = 3, format = "f", decimal.mark = ","),
        " (", kevin_season_wniosek, ")")
message("- Wykresy zapisano w katalogu: ", normalizePath(fig_dir, winslash = "/", mustWork = FALSE))
message("- Tabele zapisano w katalogu: ", normalizePath(tab_dir, winslash = "/", mustWork = FALSE))
