from django.urls import path
from . import views

urlpatterns = [
    # Existing authentication
    path('', views.login_view, name='login'),
    path('logout/', views.logout_view, name='logout'),

    # Seller Registration
    path(
        'seller/register/',
        views.seller_register,
        name='seller_register'
    ),

    # Registration Complete
    path(
        'seller/registration-complete/',
        views.registration_complete,
        name='registration_complete'
    ),

    # Seller Agreement
    path(
        'seller/agreement/',
        views.seller_agreement,
        name='seller_agreement'
    ),

    # Accept & Sign
    path(
        'seller/agreement/sign/',
        views.sign_agreement,
        name='sign_agreement'
    ),

    # Agreement Success
    path(
        'seller/agreement/success/',
        views.agreement_success,
        name='agreement_success'
    ),

    # Agreement PDF
    path(
        'seller/agreement/pdf/',
        views.agreement_pdf,
        name='agreement_pdf'
    ),
]
