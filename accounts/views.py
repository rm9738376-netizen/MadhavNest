from django.shortcuts import render, redirect, get_object_or_404
from django.contrib.auth import authenticate, login, logout
from django.contrib.auth.decorators import login_required
from django.contrib import messages
from django.utils import timezone
from django.http import HttpResponse

from .models import Seller, SellerAgreement


# =========================================================
# EXISTING LOGIN
# =========================================================

def login_view(request):

    if request.method == "POST":

        username = request.POST.get("username")
        password = request.POST.get("password")

        user = authenticate(
            request,
            username=username,
            password=password
        )

        if user:
            login(request, user)
            return redirect("/dashboard/")

        return render(
            request,
            "login.html",
            {
                "error": "Invalid Username or Password"
            }
        )

    return render(
        request,
        "login.html"
    )


# =========================================================
# EXISTING LOGOUT
# =========================================================

def logout_view(request):
    logout(request)
    return redirect("/")


# =========================================================
# SELLER REGISTRATION
# =========================================================

def seller_register(request):

    if request.method == "POST":

        full_name = request.POST.get("full_name", "").strip()
        business_name = request.POST.get("business_name", "").strip()
        email = request.POST.get("email", "").strip()
        mobile = request.POST.get("mobile", "").strip()

        address = request.POST.get("address", "").strip()
        city = request.POST.get("city", "").strip()
        state = request.POST.get("state", "").strip()
        pincode = request.POST.get("pincode", "").strip()

        gst_number = request.POST.get("gst_number", "").strip()
        pan_number = request.POST.get("pan_number", "").strip()

        if not full_name:
            return render(
                request,
                "seller_register.html",
                {"error": "Full Name is required."}
            )

        if not email:
            return render(
                request,
                "seller_register.html",
                {"error": "Email is required."}
            )

        if not mobile:
            return render(
                request,
                "seller_register.html",
                {"error": "Mobile number is required."}
            )

        if Seller.objects.filter(email=email).exists():
            return render(
                request,
                "seller_register.html",
                {"error": "A seller with this email already exists."}
            )

        seller = Seller.objects.create(
            full_name=full_name,
            business_name=business_name,
            email=email,
            mobile=mobile,
            address=address,
            city=city,
            state=state,
            pincode=pincode,
            gst_number=gst_number,
            pan_number=pan_number,
            status="agreement_pending"
        )

        # Keep seller reference in session so the next
        # agreement page knows which seller is completing it.
        request.session["seller_id"] = seller.id

        return redirect("/seller/registration-complete/")

    return render(
        request,
        "seller_register.html"
    )


# =========================================================
# REGISTRATION COMPLETE
# =========================================================

def registration_complete(request):

    seller_id = request.session.get("seller_id")

    if not seller_id:
        return redirect("/seller/register/")

    seller = get_object_or_404(
        Seller,
        id=seller_id
    )

    return render(
        request,
        "registration_complete.html",
        {
            "seller": seller
        }
    )


# =========================================================
# 1 YEAR AGREEMENT
# =========================================================

def seller_agreement(request):

    seller_id = request.session.get("seller_id")

    if not seller_id:
        return redirect("/seller/register/")

    seller = get_object_or_404(
        Seller,
        id=seller_id
    )

    agreement, created = SellerAgreement.objects.get_or_create(
        seller=seller,
        defaults={
            "start_date": timezone.localdate(),
            "status": "pending"
        }
    )

    # Signed agreements must not be edited.
    if agreement.signed:
        return redirect("/seller/agreement/success/")

    return render(
        request,
        "seller_agreement.html",
        {
            "seller": seller,
            "agreement": agreement
        }
    )


# =========================================================
# ACCEPT & SIGN AGREEMENT
# =========================================================

def sign_agreement(request):

    if request.method != "POST":
        return redirect("/seller/agreement/")

    seller_id = request.session.get("seller_id")

    if not seller_id:
        return redirect("/seller/register/")

    seller = get_object_or_404(
        Seller,
        id=seller_id
    )

    agreement = get_object_or_404(
        SellerAgreement,
        seller=seller
    )

    # Prevent duplicate signing.
    if agreement.signed:
        return redirect("/seller/agreement/success/")

    terms_accepted = request.POST.get("terms_accepted")
    signature_data = request.POST.get("signature_data", "").strip()

    if terms_accepted != "on":
        messages.error(
            request,
            "You must accept the Terms & Conditions."
        )

        return redirect("/seller/agreement/")

    if not signature_data:
        messages.error(
            request,
            "Electronic Signature is required."
        )

        return redirect("/seller/agreement/")

    # Preserve seller information at the exact time of signing.
    agreement.seller_name_snapshot = seller.full_name
    agreement.business_name_snapshot = seller.business_name
    agreement.email_snapshot = seller.email
    agreement.mobile_snapshot = seller.mobile
    agreement.address_snapshot = seller.address
    agreement.gst_number_snapshot = seller.gst_number
    agreement.pan_number_snapshot = seller.pan_number

    agreement.signature_data = signature_data
    agreement.terms_accepted = True
    agreement.signed = True
    agreement.signed_at = timezone.now()
    agreement.status = "signed"

    agreement.save()

    seller.status = "signed"
    seller.save(update_fields=["status"])

    return redirect("/seller/agreement/success/")


# =========================================================
# AGREEMENT SUCCESS
# =========================================================

def agreement_success(request):

    seller_id = request.session.get("seller_id")

    if not seller_id:
        return redirect("/seller/register/")

    seller = get_object_or_404(
        Seller,
        id=seller_id
    )

    agreement = get_object_or_404(
        SellerAgreement,
        seller=seller
    )

    if not agreement.signed:
        return redirect("/seller/agreement/")

    return render(
        request,
        "agreement_success.html",
        {
            "seller": seller,
            "agreement": agreement
        }
    )


# =========================================================
# AGREEMENT PDF
# =========================================================

def agreement_pdf(request):

    seller_id = request.session.get("seller_id")

    if not seller_id:
        return redirect("/seller/register/")

    seller = get_object_or_404(
        Seller,
        id=seller_id
    )

    agreement = get_object_or_404(
        SellerAgreement,
        seller=seller
    )

    if not agreement.signed:
        return redirect("/seller/agreement/")

    try:
        from reportlab.pdfgen import canvas
    except ImportError:
        return HttpResponse(
            "PDF generation is not configured. Please install reportlab."
        )

    response = HttpResponse(
        content_type="application/pdf"
    )

    response["Content-Disposition"] = (
        f'attachment; filename="Agreement-{agreement.agreement_number}.pdf"'
    )

    pdf = canvas.Canvas(response)

    pdf.setTitle(
        f"Seller Agreement - {agreement.agreement_number}"
    )

    y = 800

    pdf.setFont("Helvetica-Bold", 18)
    pdf.drawString(
        50,
        y,
        "Madhav Ecom Solution"
    )

    y -= 40

    pdf.setFont("Helvetica-Bold", 14)
    pdf.drawString(
        50,
        y,
        "1-Year Seller Service Agreement"
    )

    y -= 35

    pdf.setFont("Helvetica", 10)

    details = [
        f"Agreement ID: {agreement.agreement_number}",
        f"Seller ID: {seller.seller_id}",
        f"Seller Name: {seller.full_name}",
        f"Business Name: {seller.business_name}",
        f"Email: {seller.email}",
        f"Mobile: {seller.mobile}",
        f"GST Number: {seller.gst_number}",
        f"Agreement Start Date: {agreement.start_date}",
        f"Agreement End Date: {agreement.end_date}",
        f"Signed At: {agreement.signed_at}",
        "Status: SIGNED",
    ]

    for line in details:
        pdf.drawString(50, y, line)
        y -= 20

    y -= 15

    pdf.setFont("Helvetica-Bold", 11)
    pdf.drawString(
        50,
        y,
        "Terms & Conditions"
    )

    y -= 25

    pdf.setFont("Helvetica", 9)

    terms = [
        "1. Service Scope: Madhav Ecom Solution will provide agreed e-commerce",
        "   listing, catalog, account management or related services.",
        "",
        "2. Seller Responsibilities: The seller must provide accurate business,",
        "   product, tax and account information.",
        "",
        "3. Product & Listing Responsibilities: The seller is responsible for",
        "   product authenticity, pricing, stock and information supplied.",
        "",
        "4. Orders, Returns & Cancellations: Seller responsibilities will follow",
        "   the agreed service process and applicable platform requirements.",
        "",
        "5. Payment & Commercial Terms: Applicable fees/commission will be",
        "   governed by the commercial terms agreed with the seller.",
        "",
        "6. Confidentiality: Both parties should protect confidential business",
        "   information received during the service relationship.",
        "",
        "7. Intellectual Property: Each party retains rights to its own materials",
        "   except where otherwise agreed in writing.",
        "",
        "8. Term & Termination: This agreement has a one-year term beginning",
        "   on the stated start date, subject to applicable termination terms.",
        "",
        "9. Limitation of Liability: Liability will be limited to the extent",
        "   permitted by applicable law and the agreed commercial terms.",
        "",
        "10. Dispute Resolution: Disputes should first be addressed through",
        "    good-faith discussion between the parties.",
        "",
        "11. General Terms: Changes to this agreement should be documented",
        "    appropriately and accepted by the relevant parties.",
    ]

    for line in terms:

        if y < 70:
            pdf.showPage()
            y = 800
            pdf.setFont("Helvetica", 9)

        pdf.drawString(50, y, line)
        y -= 14

    y -= 20

    pdf.setFont("Helvetica-Bold", 10)

    pdf.drawString(
        50,
        y,
        "Electronic Signature / Digital Acceptance"
    )

    y -= 20

    pdf.setFont("Helvetica", 9)

    pdf.drawString(
        50,
        y,
        "The seller electronically accepted the agreement and Terms & Conditions."
    )

    y -= 20

    pdf.drawString(
        50,
        y,
        f"Accepted By: {seller.full_name}"
    )

    y -= 18

    pdf.drawString(
        50,
        y,
        f"Acceptance Time: {agreement.signed_at}"
    )

    pdf.save()

    return response
