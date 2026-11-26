|model       |label            |parameter |search_grid                |selected |
|:-----------|:----------------|:---------|:--------------------------|:--------|
|M0_baseline |M0 Baseline      |(none)    |predicts the training mean |—        |
|M1_lm       |M1 Linear        |(none)    |ordinary least squares     |—        |
|M2_knn      |M2 k-NN          |k         |1, 2, …, 20                |8        |
|M3_rf       |M3 Random Forest |mtry      |1, 2, …, 5                 |5        |
|M3_rf       |M3 Random Forest |ntree     |fixed                      |500      |
|M4_svr      |M4 SVR           |C         |2^-2, 2^-1, …, 2^6         |32       |
|M4_svr      |M4 SVR           |sigma     |0.01, 0.05, 0.1, 0.5, 1    |0.01     |
