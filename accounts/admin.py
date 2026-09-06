from django.contrib import admin
from .models import Seller, SellerAgreement


@admin.register(Seller)
class SellerAdmin(admin.ModelAdmin):
    list_display = (
        "seller_id",
        "full_name",
        "business_name",
        "email",
        "mobile",
        "status",
        "registration_date",
    )

    search_fields = (
        "seller_id",
        "full_name",
        "business_name",
        "email",
        "mobile",
        "gst_number",
        "pan_number",
    )

    list_filter = (
        "status",
        "registration_date",
    )

    readonly_fields = (
        "seller_id",
        "registration_date",
    )


@admin.register(SellerAgreement)
class SellerAgreementAdmin(admin.ModelAdmin):
    list_display = (
        "agreement_number",
        "seller",
        "start_date",
        "end_date",
        "signed",
        "terms_accepted",
        "status",
    )

    search_fields = (
        "agreement_number",
        "seller__seller_id",
        "seller__full_name",
        "seller__business_name",
        "seller__email",
    )

    list_filter = (
        "signed",
        "terms_accepted",
        "status",
    )

    readonly_fields = (
        "agreement_number",
        "created_at",
        "updated_at",
    )
