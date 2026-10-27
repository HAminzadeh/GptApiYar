package ir.gptapiyar.bridge.security;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.web.servlet.HandlerInterceptor;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

@Configuration
public class LocalSecurityConfig implements WebMvcConfigurer {
    @Value("${gateway.token}")
    private String gatewayToken;

    @Override
    public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping("/api/**")
            .allowedOrigins("http://127.0.0.1:5173", "http://localhost:5173")
            .allowedMethods("GET", "POST", "OPTIONS")
            .allowedHeaders("X-Gateway-Token", "Content-Type");
    }

    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        registry.addInterceptor(new HandlerInterceptor() {
            @Override
            public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws Exception {
                if (HttpMethod.OPTIONS.matches(request.getMethod())) return true;
                if (gatewayToken.equals(request.getHeader("X-Gateway-Token"))) return true;
                response.setStatus(401);
                response.setContentType("application/json; charset=utf-8");
                response.getWriter().write("{\"error\":\"Missing or invalid X-Gateway-Token\"}");
                return false;
            }
        }).addPathPatterns("/api/**");
    }
}
