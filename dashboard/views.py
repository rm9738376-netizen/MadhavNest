from django.shortcuts import render
import pandas as pd


def home(request):

    context = {
        "total_orders": 0,
        "total_sales": 0,
        "profit": 0,
        "avg_profit": 0,
        "profit_percent": 0,
        "returns": 0,
        "rto": 0,
        "delivered_orders": 0,
        "return_percent": 0,
        "rto_percent": 0,
    }

    if request.method == "POST":

        try:

            report_file = request.FILES["excel_file"]

            if report_file.name.endswith(".csv"):
                df = pd.read_csv(report_file, skiprows=2)

            elif report_file.name.endswith(".xlsx"):
                df = pd.read_excel(
                    report_file,
                    engine="openpyxl",
                    skiprows=2
                )

            else:
                return render(
                    request,
                    "dashboard/home.html",
                    {"error": "Unsupported File Format"}
                )

            total_orders = len(df)

            sale_column = df.columns[15]
            total_sales = round(
                pd.to_numeric(
                    df[sale_column],
                    errors="coerce"
                ).fillna(0).sum(),
                2
            )

            profit_column = df.columns[13]
            profit = round(
                pd.to_numeric(
                    df[profit_column],
                    errors="coerce"
                ).fillna(0).sum(),
                2
            )

            status_column = df.columns[7]

            returns = len(
                df[
                    df[status_column]
                    .astype(str)
                    .str.contains("Return", case=False, na=False)
                ]
            )

            rto = len(
                df[
                    df[status_column]
                    .astype(str)
                    .str.contains("RTO", case=False, na=False)
                ]
            )

            delivered_orders = total_orders - returns - rto

            avg_profit = 0
            if total_orders > 0:
                avg_profit = round(
                    profit / total_orders,
                    2
                )

            profit_percent = 0
            if total_sales > 0:
                profit_percent = round(
                    (profit / total_sales) * 100,
                    2
                )

            return_percent = 0
            rto_percent = 0

            if total_orders > 0:
                return_percent = round(
                    (returns / total_orders) * 100,
                    2
                )

                rto_percent = round(
                    (rto / total_orders) * 100,
                    2
                )

            context = {
                "total_orders": total_orders,
                "total_sales": total_sales,
                "profit": profit,
                "avg_profit": avg_profit,
                "profit_percent": profit_percent,
                "returns": returns,
                "rto": rto,
                "delivered_orders": delivered_orders,
                "return_percent": return_percent,
                "rto_percent": rto_percent,
            }

        except Exception as e:
            print("ERROR =", e)

    return render(
        request,
        "dashboard/home.html",
        context
    )