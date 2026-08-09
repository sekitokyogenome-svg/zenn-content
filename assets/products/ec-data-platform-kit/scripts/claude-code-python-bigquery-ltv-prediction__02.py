"""Claude Code × Python × BigQueryでLTV予測モデルを作った

出典記事: articles/claude-code-python-bigquery-ltv-prediction.md
実行前に認証情報と ${PROJECT} / ${DATASET} を設定すること。
"""

"""
モジュール名: ltv_regression_model.py
目的: 回帰モデルでLTV予測を行う
作成日: 2026-03-30
依存: google-cloud-bigquery, pandas, scikit-learn
"""

import pandas as pd
import numpy as np
from sklearn.ensemble import GradientBoostingRegressor
from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_absolute_error, r2_score
from sklearn.preprocessing import LabelEncoder

def prepare_features(rfm_df: pd.DataFrame, behavior_df: pd.DataFrame) -> pd.DataFrame:
    """特徴量を準備する"""
    # RFMデータとセッション行動データを結合
    merged = rfm_df.merge(behavior_df, on='user_pseudo_id', how='left')

    # カテゴリ変数のエンコード
    le_medium = LabelEncoder()
    le_device = LabelEncoder()
    merged['medium_encoded'] = le_medium.fit_transform(merged['first_medium'].fillna('(none)'))
    merged['device_encoded'] = le_device.fit_transform(merged['device_category'].fillna('(none)'))

    # 特徴量の選定
    features = [
        'frequency', 'recency_days', 'tenure_days', 'avg_order_value',
        'total_sessions', 'view_item_count', 'add_to_cart_count',
        'page_view_count', 'medium_encoded', 'device_encoded'
    ]

    return merged, features

def train_ltv_model(df: pd.DataFrame, features: list[str], target: str = 'monetary'):
    """LTV予測モデルを学習する"""
    X = df[features].fillna(0)
    y = df[target]

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )

    model = GradientBoostingRegressor(
        n_estimators=200,
        max_depth=5,
        learning_rate=0.1,
        random_state=42
    )
    model.fit(X_train, y_train)

    # 評価
    y_pred = model.predict(X_test)
    mae = mean_absolute_error(y_test, y_pred)
    r2 = r2_score(y_test, y_pred)

    print(f"モデル評価:")
    print(f"  MAE: ¥{mae:,.0f}")
    print(f"  R²スコア: {r2:.3f}")

    # 特徴量重要度
    importance = pd.DataFrame({
        'feature': features,
        'importance': model.feature_importances_
    }).sort_values('importance', ascending=False)

    print(f"\n特徴量重要度:")
    for _, row in importance.iterrows():
        print(f"  {row['feature']}: {row['importance']:.3f}")

    return model, importance
