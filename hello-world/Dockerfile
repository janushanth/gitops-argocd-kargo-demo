FROM public.ecr.aws/docker/library/nginx:1.27.5
ARG VERSION=0.0.0
RUN echo "<h1>Hello World</h1><p>version ${VERSION}</p>" > /usr/share/nginx/html/index.html
EXPOSE 80
