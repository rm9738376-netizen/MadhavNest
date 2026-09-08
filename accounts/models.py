from datetime import timedelta

from django.db import models
from django.utils import timezone


class Seller(models.Model):
    STATUS_CHOICES = [
        ("registered", "Registered"),
        ("agreement_pending", "Agreement Pending"),
        ("signed", "Agreement Signed"),
        ("active", "Active"),
    ]

    seller_id = models.CharField(
        max_length=30,
        unique=True,
        blank=True
    )

    full_name = models.CharField(max_length=150)
    business_name = models.CharField(max_length=200, blank=True)
    email = models.EmailField(unique=True)
    mobile = models.CharField(max_length=15)

    address = models.TextField(blank=True)
    city = models.CharField(max_length=100, blank=True)
    state = models.CharField(max_length=100, blank=True)
    pincode = models.CharField(max_length=10, blank=True)

    gst_number = models.CharField(max_length=20, blank=True)
    pan_number = models.CharField(max_length=20, blank=True)

    registration_date = models.DateTimeField(
        default=timezone.now
    )

    status = models.CharField(
        max_length=30,
        choices=STATUS_CHOICES,
        default="registered"
    )

    def save(self, *args, **kwargs):
        if not self.seller_id:
            last_seller = Seller.objects.order_by("-id").first()

            if last_seller and last_seller.seller_id:
                try:
                    last_number = int(
                        last_seller.seller_id.replace("MES-", "")
                    )
                except ValueError:
                    last_number = 0
            else:
                last_number = 0

            self.seller_id = f"MES-{last_number + 1:05d}"

        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.seller_id} - {self.full_name}"


class SellerAgreement(models.Model):
    AGREEMENT_STATUS = [
        ("pending", "Pending"),
        ("signed", "Signed"),
        ("active", "Active"),
        ("expired", "Expired"),
        ("terminated", "Terminated"),
    ]

    seller = models.OneToOneField(
        Seller,
        on_delete=models.CASCADE,
        related_name="agreement"
    )

    agreement_number = models.CharField(
        max_length=40,
        unique=True,
        blank=True
    )

    start_date = models.DateField(
        blank=True,
        null=True
    )

    end_date = models.DateField(
        blank=True,
        null=True
    )

    agreement_version = models.CharField(
        max_length=20,
        default="1.0"
    )

    # ---------------------------------------------------------
    # SELLER SNAPSHOT
    # These fields preserve seller information at signing time.
    # ---------------------------------------------------------

    seller_id_snapshot = models.CharField(
        max_length=30,
        blank=True
    )

    seller_name_snapshot = models.CharField(
        max_length=150,
        blank=True
    )

    business_name_snapshot = models.CharField(
        max_length=200,
        blank=True
    )

    email_snapshot = models.EmailField(
        blank=True
    )

    mobile_snapshot = models.CharField(
        max_length=15,
        blank=True
    )

    address_snapshot = models.TextField(
        blank=True
    )

    city_snapshot = models.CharField(
        max_length=100,
        blank=True
    )

    state_snapshot = models.CharField(
        max_length=100,
        blank=True
    )

    pincode_snapshot = models.CharField(
        max_length=10,
        blank=True
    )

    gst_number_snapshot = models.CharField(
        max_length=20,
        blank=True
    )

    pan_number_snapshot = models.CharField(
        max_length=20,
        blank=True
    )

    # ---------------------------------------------------------
    # ACCEPTANCE / SIGNATURE
    # ---------------------------------------------------------

    terms_accepted = models.BooleanField(
        default=False
    )

    signed = models.BooleanField(
        default=False
    )

    signature_name = models.CharField(
        max_length=150,
        blank=True
    )

    # Browser canvas signature data
    signature_data = models.TextField(
        blank=True
    )

    signed_at = models.DateTimeField(
        blank=True,
        null=True
    )

    # IP captured at signing time
    signed_ip = models.GenericIPAddressField(
        blank=True,
        null=True
    )

    status = models.CharField(
        max_length=20,
        choices=AGREEMENT_STATUS,
        default="pending"
    )

    # ---------------------------------------------------------
    # PDF
    # ---------------------------------------------------------

    pdf_file = models.FileField(
        upload_to="agreements/",
        blank=True,
        null=True
    )

    created_at = models.DateTimeField(
        auto_now_add=True
    )

    updated_at = models.DateTimeField(
        auto_now=True
    )

    def save(self, *args, **kwargs):

        # Generate unique agreement number
        if not self.agreement_number:
            last_agreement = (
                SellerAgreement.objects
                .order_by("-id")
                .first()
            )

            if (
                last_agreement
                and last_agreement.agreement_number
            ):
                try:
                    last_number = int(
                        last_agreement.agreement_number.replace(
                            "MES-AGR-",
                            ""
                        )
                    )
                except ValueError:
                    last_number = 0
            else:
                last_number = 0

            self.agreement_number = (
                f"MES-AGR-{last_number + 1:05d}"
            )

        # -----------------------------------------------------
        # 1-YEAR AGREEMENT
        # Use calendar-year anniversary rather than simply
        # adding 365 days.
        # -----------------------------------------------------

        if self.start_date and not self.end_date:
            try:
                self.end_date = self.start_date.replace(
                    year=self.start_date.year + 1
                )
            except ValueError:
                # Handles February 29 -> February 28
                self.end_date = (
                    self.start_date
                    + timedelta(days=365)
                )

        super().save(*args, **kwargs)

    def __str__(self):
        return self.agreement_number
