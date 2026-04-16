# cloudfront.tf
# Defines the CloudFront CDN (Content Delivery Network) distribution.
#
# CloudFront sits in front of the S3 frontend bucket and provides:
#   - HTTPS: S3 static websites only serve over HTTP; CloudFront adds HTTPS
#   - Global edge caching: files are served from AWS locations near the user
#   - SPA routing support: redirects 403/404 errors to index.html so Next.js
#     can handle client-side routing (e.g., navigating directly to /chat)
#
# Request flow for the frontend:
#   User browser → CloudFront edge node → S3 bucket → HTML/JS/CSS files

resource "aws_cloudfront_distribution" "twin" {
  enabled             = true
  default_root_object = "index.html"  # Serve index.html when the root URL "/" is requested

  # PriceClass_100 restricts CloudFront to edge locations in North America and Europe only.
  # This reduces cost while still covering typical users. PriceClass_All uses every
  # edge location worldwide (faster globally, but more expensive).
  price_class = "PriceClass_100"

  # ─── Origin: where CloudFront fetches files from ─────────────────────────
  # We use the S3 website endpoint (not the raw bucket endpoint).
  # The website endpoint supports index.html redirects for subdirectories,
  # which the raw bucket endpoint does not understand.
  origin {
    domain_name = aws_s3_bucket_website_configuration.frontend.website_endpoint
    origin_id   = local.s3_origin_id  # A local label used to link this origin to cache behaviours below

    custom_origin_config {
      http_port  = 80
      https_port = 443

      # "http-only": CloudFront fetches from S3 over plain HTTP.
      # This does NOT create a security problem because:
      #   1. The viewer → CloudFront connection is always HTTPS (enforced below with redirect-to-https)
      #   2. The CloudFront → S3 connection travels over AWS's internal private network —
      #      it never touches the public internet, so it cannot be intercepted
      #   3. The content is public frontend assets (HTML/JS/CSS) — not sensitive data
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # ─── Cache Behaviour: how CloudFront handles requests ────────────────────
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]   # Only read operations — no POST/PUT to S3
    cached_methods         = ["GET", "HEAD"]   # Cache GET and HEAD responses at the edge
    target_origin_id       = local.s3_origin_id

    # redirect-to-https: if a user types http:// in the browser, CloudFront
    # automatically redirects them to the https:// version. Viewers always get HTTPS.
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      # Don't forward query strings to S3 — static files don't use them
      query_string = false
      cookies { forward = "none" }  # Don't forward cookies to S3
    }
  }

  # ─── SPA Routing Fix ─────────────────────────────────────────────────────
  # Without these blocks, navigating directly to https://xyz.cloudfront.net/chat
  # would fail with a raw AWS error page. Here is why:
  #
  #   1. CloudFront asks S3 for the file at path "/chat"
  #   2. S3 has no file called "chat" — it returns 403 Forbidden (or 404 Not Found)
  #   3. CloudFront would normally pass that error back to the browser
  #
  # The fix: intercept 403 and 404 responses from S3 and return index.html instead
  # with a 200 OK status. Then the Next.js JavaScript running in the browser reads
  # the URL path (/chat) and renders the correct page client-side.
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    # No geographic restrictions — available to users everywhere
    geo_restriction { restriction_type = "none" }
  }

  # Use CloudFront's free default SSL certificate (*.cloudfront.net).
  # For a custom domain (e.g., twin.yourname.com), you would provision an
  # ACM (AWS Certificate Manager) certificate and reference it here instead.
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  }
}
